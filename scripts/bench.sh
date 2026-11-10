#!/usr/bin/env bash
# Throughput and latency of the same Laravel app on PAM, FrankenPHP, Swoole
# and RoadRunner, all started with `artisan octane:start --server=...`.
# One server at a time, ROUNDS rounds, the server order rotating per round.
source "$(dirname "$0")/lib.sh"
RAW="$RESULTS/raw"
mkdir -p "$RAW"
CSV="$RESULTS/bench.csv"
echo "round,server,time_utc,load1,load5,load15" > "$RESULTS/load.csv"
echo "round,server,endpoint,rps,p50_ms,p99_ms,errors,memory_current_mib,memory_peak_mib" > "$CSV"
read -r -a servers <<< "$SERVERS"
read -r -a endpoints <<< "$ENDPOINTS"

start_server() {
    local server="$1"
    local -a run=(docker run -d --rm --name "bench-$server" --network host --cpuset-cpus "$SERVER_CPUS"
        --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$APP:$APP" -w "$APP")
    local -a octane=(artisan octane:start "--server=$server" --host=127.0.0.1 "--port=$PORT"
        "--workers=$WORKERS" --max-requests=10000000)
    case "$server" in
        pam) "${run[@]}" "$IMAGE_PAM" pam "${octane[@]}" ;;
        frankenphp) "${run[@]}" "$IMAGE_FRANKENPHP" php "${octane[@]}" --admin-port=2119 ;;
        swoole) "${run[@]}" "$IMAGE_PHP" php "${octane[@]}" --task-workers=1 ;;
        roadrunner) "${run[@]}" "$IMAGE_PHP" php "${octane[@]}" --rpc-port=6101 ;;
    esac >/dev/null
    wait_http "http://127.0.0.1:$PORT/_r/hello" 90
}

memory_mib() {
    local id cg
    id=$(docker inspect -f '{{.Id}}' "bench-$1")
    for cg in "/sys/fs/cgroup/system.slice/docker-$id.scope" "/sys/fs/cgroup/docker/$id"; do
        if [ -r "$cg/memory.current" ]; then
            echo "$(( $(cat "$cg/memory.current") / 1048576 )) $(( $(cat "$cg/memory.peak" 2>/dev/null || echo 0) / 1048576 ))"
            return
        fi
    done
    echo "0 0"
}

for round in $(seq 1 "$ROUNDS"); do
    shift_by=$(( (round - 1) % ${#servers[@]} ))
    order=("${servers[@]:$shift_by}" "${servers[@]:0:$shift_by}")
    mkdir -p "$RAW/round-$round"
    for server in "${order[@]}"; do
        log "round $round/$ROUNDS: $server"
        echo "$round,$server,$(date -u +%H:%M:%S),$(cut -d' ' -f1-3 /proc/loadavg | tr ' ' ',')" >> "$RESULTS/load.csv"
        docker rm -f "bench-$server" >/dev/null 2>&1 || true
        start_server "$server"
        for endpoint in "${endpoints[@]}"; do
            url="http://127.0.0.1:$PORT/_r/$endpoint"
            out="$RAW/round-$round/$server-$endpoint.txt"
            taskset -c "$LOAD_CPUS" wrk -t"$WRK_THREADS" -c"$WRK_CONNECTIONS" -d"$WARMUP" "$url" >/dev/null 2>&1
            taskset -c "$LOAD_CPUS" wrk -t"$WRK_THREADS" -c"$WRK_CONNECTIONS" -d"$DURATION" --latency "$url" > "$out" 2>&1
            read -r current peak < <(memory_mib "$server")
            python3 "$ROOT/scripts/parse_wrk.py" "$out" "$round" "$server" "$endpoint" "$current" "$peak" | tee -a "$CSV"
        done
        docker logs "bench-$server" > "$RAW/round-$round/$server.log" 2>&1 || true
        docker rm -f "bench-$server" >/dev/null
        sleep 3
    done
done
bash "$ROOT/scripts/machine.sh" end >/dev/null
python3 "$ROOT/scripts/report.py" "$RESULTS"
