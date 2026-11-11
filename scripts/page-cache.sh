#!/usr/bin/env bash
# PAM's edge page cache: the `view` endpoint (Blade, 20 items) rendered by PHP
# on every request, and the same page marked `Cache-Control: public,
# s-maxage=60` (`/_r/view-cached`) with the cache on, served from PAM's Rust
# HTTP layer without entering PHP. The cache is enabled through the
# pushinbr/pam-octane bridge (`PAM_RESPONSE_CACHE=true`), installed in a copy of
# the benchmark app; Octane's PAM driver does not expose it. Same CPUs, workers
# and wrk settings as bench.sh.
source "$(dirname "$0")/lib.sh"
OUT="$RESULTS/page-cache"
CACHE_APP="$WORK/app-pam-octane"
mkdir -p "$OUT/raw"

if [ ! -f "$CACHE_APP/vendor/pushinbr/pam-octane/composer.json" ]; then
    log "provisioning $CACHE_APP (pushinbr/pam-octane $PAM_OCTANE_VERSION)"
    rm -rf "$CACHE_APP"; cp -a "$APP" "$CACHE_APP"
    docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e COMPOSER_HOME=/tmp/composer \
        -v "$CACHE_APP:$CACHE_APP" -w "$CACHE_APP" "$IMAGE_PHP" sh -ec "
        rm -f bootstrap/cache/*.php
        composer require --no-interaction -W --no-scripts \
            'laravel/octane:dev-2.x-pam#$OCTANE_REF as 2.99.0' 'pushinbr/pam-octane:$PAM_OCTANE_VERSION' >/dev/null 2>&1
        composer run-script post-autoload-dump >/dev/null
        php artisan optimize -q
        composer show pushinbr/pam-octane | grep -E '^(versions|source)'
    "
fi

echo "round,cache,endpoint,rps,p50_ms,p99_ms,errors,memory_current_mib,memory_peak_mib" > "$OUT/page-cache.csv"
for round in $(seq 1 "$ROUNDS"); do
    for cache in true false; do
        log "page cache round $round/$ROUNDS: PAM_RESPONSE_CACHE=$cache"
        docker rm -f bench-pagecache >/dev/null 2>&1 || true
        docker run -d --rm --name bench-pagecache --network host --cpuset-cpus "$SERVER_CPUS" \
            --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$CACHE_APP:$CACHE_APP" -w "$CACHE_APP" \
            -e PAM_RESPONSE_CACHE="$cache" -e PAM_RESPONSE_CACHE_STATUS_HEADER=true "$IMAGE_PAM" \
            pam start artisan --workers "$WORKERS" --max-requests 10000000 -- pam:octane --host=127.0.0.1 "--port=$PORT" >/dev/null
        wait_http "http://127.0.0.1:$PORT/_r/hello" 90
        curl -fsS -D - -o /dev/null "http://127.0.0.1:$PORT/_r/view-cached" > "$OUT/raw/headers-$cache-$round.txt"
        curl -fsS -D - -o /dev/null "http://127.0.0.1:$PORT/_r/view-cached" >> "$OUT/raw/headers-$cache-$round.txt"
        for endpoint in view view-cached; do
            url="http://127.0.0.1:$PORT/_r/$endpoint"
            raw="$OUT/raw/round-$round-cache-$cache-$endpoint.txt"
            taskset -c "$LOAD_CPUS" wrk -t"$WRK_THREADS" -c"$WRK_CONNECTIONS" -d"$WARMUP" "$url" >/dev/null 2>&1
            taskset -c "$LOAD_CPUS" wrk -t"$WRK_THREADS" -c"$WRK_CONNECTIONS" -d"$DURATION" --latency "$url" > "$raw" 2>&1
            id=$(docker inspect -f '{{.Id}}' bench-pagecache)
            cg="/sys/fs/cgroup/system.slice/docker-$id.scope"
            [ -r "$cg/memory.current" ] || cg="/sys/fs/cgroup/docker/$id"
            python3 "$ROOT/scripts/parse_wrk.py" "$raw" "$round" "cache-$cache" "$endpoint" \
                "$(( $(cat "$cg/memory.current") / 1048576 ))" "$(( $(cat "$cg/memory.peak" 2>/dev/null || echo 0) / 1048576 ))" \
                | sed "s/,cache-$cache,/,$cache,/" | tee -a "$OUT/page-cache.csv"
        done
        docker logs bench-pagecache > "$OUT/raw/server-$cache-$round.log" 2>&1 || true
        docker rm -f bench-pagecache >/dev/null
        sleep 3
    done
done
