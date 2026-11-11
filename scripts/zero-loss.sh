#!/usr/bin/env bash
# Zero-loss reload and recycling, with net.ipv4.tcp_migrate_req=1 and =0, with
# keep-alive connections and with a new connection per request, in the PAM
# container's own network namespace:
#   reload:  wrk against `octane:start --server=pam --workers=4
#            --max-requests=2000` while `octane:reload --server=pam` runs every
#            4 seconds. A run without any successful reload fails.
#   recycle: the same without reloads and with --max-requests=500, so every
#            worker is replaced every few hundred milliseconds.
source "$(dirname "$0")/lib.sh"
SECONDS_PER_RUN="${ZERO_LOSS_SECONDS:-60}"
OUT="$RESULTS/zero-loss"
mkdir -p "$OUT"
echo "scenario,tcp_migrate_req,connections,requests,socket_errors,non_2xx,reloads,failed_reloads,rps" > "$OUT/zero-loss.csv"
status=0

for scenario in ${ZERO_LOSS_SCENARIOS:-reload recycle}; do
for migrate in 1 0; do
    for mode in keep-alive close; do
        log "zero-loss: $scenario, tcp_migrate_req=$migrate, $mode"
        max_requests=2000; reload_every=4
        [ "$scenario" = recycle ] && { max_requests=500; reload_every=0; }
        header=""
        [ "$mode" = close ] && header="-H 'Connection: close'"
        docker rm -f bench-zero-loss >/dev/null 2>&1 || true
        timeout $((SECONDS_PER_RUN + 120)) docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$APP:$APP" -w "$APP" \
            --name bench-zero-loss --cpuset-cpus 0-11 --sysctl "net.ipv4.tcp_migrate_req=$migrate" \
            "$IMAGE_PAM" bash -c "
            echo \"tcp_migrate_req=\$(cat /proc/sys/net/ipv4/tcp_migrate_req)\"
            pam artisan octane:start --server=pam --host=127.0.0.1 --port=8500 --workers=4 --max-requests=$max_requests > /tmp/server.log 2>&1 &
            until curl -fs -o /dev/null http://127.0.0.1:8500/_r/hello; do sleep 0.3; done
            (
                ok=0; failed=0; end=\$((SECONDS + $SECONDS_PER_RUN - 2)); sleep 4
                while [ $reload_every -gt 0 ] && [ \$SECONDS -lt \$end ]; do
                    if timeout 20 pam artisan octane:reload --server=pam >> /tmp/reload.log 2>&1; then ok=\$((ok + 1)); else failed=\$((failed + 1)); fi
                    sleep 4
                done
                echo \"\$ok \$failed\" > /tmp/reloads
            ) &
            reloader=\$!
            taskset -c 8-11 wrk -t4 -c64 -d${SECONDS_PER_RUN}s $header --latency http://127.0.0.1:8500/_r/hello
            wait \$reloader
            read ok failed < /tmp/reloads
            echo RELOADS=\$ok FAILED_RELOADS=\$failed
            echo '--- reload log'; grep -v '^\s*$' /tmp/reload.log | sort | uniq -c
            timeout 30 pam artisan octane:stop --server=pam
            echo '--- server log'; grep -v '^\s*$' /tmp/server.log | grep -v ' GET ' | tail -30
        " > "$OUT/$scenario-migrate-$migrate-$mode.txt" 2>&1 || true
        docker rm -f bench-zero-loss >/dev/null 2>&1 || true
        python3 - "$OUT/$scenario-migrate-$migrate-$mode.txt" "$scenario" "$migrate" "$mode" >> "$OUT/zero-loss.csv" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
requests = re.search(r"(\d+) requests in", text)
socket = sum(int(x) for x in re.findall(r"(?:connect|read|write|timeout) (\d+)", text))
non2xx = re.search(r"Non-2xx or 3xx responses: (\d+)", text)
reloads = re.search(r"RELOADS=(\d+) FAILED_RELOADS=(\d+)", text)
rps = re.search(r"Requests/sec:\s+([\d.]+)", text)
print(",".join(str(x) for x in [sys.argv[2], sys.argv[3], sys.argv[4], requests.group(1) if requests else "",
      socket, non2xx.group(1) if non2xx else 0, reloads.group(1) if reloads else 0,
      reloads.group(2) if reloads else "", rps.group(1) if rps else ""]))
PY
        row=$(tail -1 "$OUT/zero-loss.csv"); echo "$row"
        if { [ "$scenario" = reload ] && [ "$(echo "$row" | cut -d, -f7)" = 0 ]; } || [ -z "$(echo "$row" | cut -d, -f4)" ]; then
            log "FAIL: no successful reload or no wrk result (see $OUT/$scenario-migrate-$migrate-$mode.txt)"; status=1
        fi
    done
done
done
exit $status
