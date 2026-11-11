#!/usr/bin/env bash
# Post-boot zygote. PAM forks workers from a booted application with
# PAM_PREFORK_BOOT=app (post-boot, the default for `artisan pam:octane`) and
# from a bare engine with PAM_PREFORK_BOOT=engine (pre-boot, the default for
# Octane's PAM driver in this PAM release).
#
# 1. Spawn, respawn and reload times: PAM runs Octane's own PAM worker
#    (vendor/laravel/octane/bin/pam-worker.php) exactly as `octane:start
#    --server=pam` starts it, plus an admin address to read readiness.
# 2. Memory: every server started with `octane:start --workers=N`, a 10 s
#    `wrk` warmup on /_r/view, then the summed PSS of the container's
#    processes and the cgroup's memory.current.
source "$(dirname "$0")/lib.sh"
OUT="$RESULTS/zygote"
mkdir -p "$OUT"
ADMIN_PORT=$((PORT + 99))
ZYGOTE_WORKERS="${ZYGOTE_WORKERS:-8 16}"
ZYGOTE_ROUNDS="${ZYGOTE_ROUNDS:-3}"

cgroup_dir() {
    local id cg
    id=$(docker inspect -f '{{.Id}}' "$1")
    for cg in "/sys/fs/cgroup/system.slice/docker-$id.scope" "/sys/fs/cgroup/docker/$id"; do
        [ -r "$cg/memory.current" ] && { echo "$cg"; return; }
    done
}

memory_json() {
    python3 - "$(cgroup_dir "$1")" <<'PY'
import json, sys
cg = sys.argv[1]
pss = 0
procs = [int(x) for x in open(f"{cg}/cgroup.procs").read().split()]
for pid in procs:
    try:
        for line in open(f"/proc/{pid}/smaps_rollup"):
            if line.startswith("Pss:"):
                pss += int(line.split()[1])
    except OSError:
        pass
print(json.dumps({"processes": len(procs), "pss_mib": round(pss / 1024, 1),
                  "memory_current_mib": round(int(open(f"{cg}/memory.current").read()) / 1048576, 1)}))
PY
}

echo "workers,round,mode,cold_start_ms,spawn_p50_ms,spawn_max_ms,respawn_p50_ms,reload_p50_ms,reload_max_ms" > "$OUT/pam-times.csv"
for workers in $ZYGOTE_WORKERS; do
    for round in $(seq 1 "$ZYGOTE_ROUNDS"); do
        for mode in app engine; do
            log "zygote times: $workers workers, round $round, PAM_PREFORK_BOOT=$mode"
            state="$OUT/state-$mode-$workers-$round"
            rm -rf "$state"; mkdir -p "$state"
            docker rm -f bench-zygote >/dev/null 2>&1 || true
            started=$(date +%s%3N)
            docker run -d --rm --name bench-zygote --network host --pid host --cpuset-cpus "$SERVER_CPUS" \
                --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$APP:$APP" -v "$state:$state" -w "$APP" \
                -e TMPDIR="$state" -e PAM_PREFORK_BOOT="$mode" -e APP_ENV=production -e APP_BASE_PATH="$APP" \
                -e LARAVEL_OCTANE=1 -e OCTANE_HOST=127.0.0.1 -e OCTANE_PORT="$PORT" -e REQUEST_MAX_EXECUTION_TIME=30 \
                "$IMAGE_PAM" pam start "$APP/vendor/laravel/octane/bin/pam-worker.php" --workers "$workers" \
                --max-requests 10000000 --admin-address "127.0.0.1:$ADMIN_PORT" >/dev/null
            python3 "$ROOT/scripts/zygote_measure.py" --admin "127.0.0.1:$ADMIN_PORT" --workers "$workers" \
                --state-dir "$state" --started-at "$started" > "$OUT/pam-$mode-$workers-$round.json"
            docker logs bench-zygote > "$OUT/pam-$mode-$workers-$round.log" 2>&1 || true
            docker rm -f bench-zygote >/dev/null
            python3 - "$OUT/pam-$mode-$workers-$round.json" "$workers" "$round" "$mode" >> "$OUT/pam-times.csv" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
print(",".join(map(str, [sys.argv[2], sys.argv[3], sys.argv[4], r["cold_start_ms"], r["spawn_to_ready_ms"]["p50"],
    r["spawn_to_ready_ms"]["max"], r["respawn_after_sigkill_ms"]["p50"], r["reload_ms"]["p50"], r["reload_ms"]["max"]])))
PY
            tail -1 "$OUT/pam-times.csv"
            rm -rf "$state"
            sleep 2
        done
    done
done

echo "workers,round,server,processes,pss_mib,memory_current_mib" > "$OUT/memory.csv"
for workers in $ZYGOTE_WORKERS; do
    for round in $(seq 1 "$ZYGOTE_ROUNDS"); do
        for server in pam-app pam-engine frankenphp swoole roadrunner; do
            log "memory: $workers workers, round $round, $server"
            docker rm -f bench-mem >/dev/null 2>&1 || true
            run=(docker run -d --rm --name bench-mem --network host --cpuset-cpus "$SERVER_CPUS"
                --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$APP:$APP" -w "$APP")
            octane=(artisan octane:start --host=127.0.0.1 "--port=$PORT" "--workers=$workers" --max-requests=10000000)
            case "$server" in
                pam-*) "${run[@]}" -e PAM_PREFORK_BOOT="${server#pam-}" "$IMAGE_PAM" pam "${octane[@]}" --server=pam ;;
                frankenphp) "${run[@]}" "$IMAGE_FRANKENPHP" php "${octane[@]}" --server=frankenphp --admin-port=2119 ;;
                swoole) "${run[@]}" "$IMAGE_PHP" php "${octane[@]}" --server=swoole --task-workers=1 ;;
                roadrunner) "${run[@]}" "$IMAGE_PHP" php "${octane[@]}" --server=roadrunner --rpc-port=6101 ;;
            esac >/dev/null
            wait_http "http://127.0.0.1:$PORT/_r/hello" 90
            taskset -c "$LOAD_CPUS" wrk -t"$WRK_THREADS" -c"$WRK_CONNECTIONS" -d10s "http://127.0.0.1:$PORT/_r/view" >/dev/null 2>&1
            sleep 2
            m=$(memory_json bench-mem)
            docker logs bench-mem > "$OUT/memory-$server-$workers-$round.log" 2>&1 || true
            docker rm -f bench-mem >/dev/null
            python3 -c "import json,sys; m=json.loads(sys.argv[1]); print(f\"$workers,$round,$server,{m['processes']},{m['pss_mib']},{m['memory_current_mib']}\")" "$m" | tee -a "$OUT/memory.csv"
            sleep 3
        done
    done
done
