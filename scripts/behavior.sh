#!/usr/bin/env bash
# PAM behavior checks through `octane:start --server=pam`: a request past
# octane.max_execution_time (2 s), `response()->send()`, a 100 MB upload cut by
# the timeout, then, with the default 30 s, 100 MB and
# 1 GB uploads with PHP's default memory_limit (128M). Runs in the PAM container.
source "$(dirname "$0")/lib.sh"
OUT="$RESULTS/behavior"
mkdir -p "$OUT"
INI_DIR=$(docker run --rm "$IMAGE_PAM" pam -r 'echo dirname(php_ini_loaded_file());')/conf.d
cat > "$WORK/behavior.ini" <<'INI'
opcache.enable=1
opcache.enable_cli=1
opcache.jit=tracing
opcache.jit_buffer_size=128M
opcache.validate_timestamps=0
memory_limit=128M
upload_max_filesize=2G
post_max_size=2G
INI
docker_run "$IMAGE_PHP" php artisan config:clear -q
docker_run --name bench-behavior --cpuset-cpus 0-11 --tmpfs /data:size=1100m \
    -v "$WORK/behavior.ini:$INI_DIR/99-bench.ini:ro" "$IMAGE_PAM" bash -c '
    U=http://127.0.0.1:8500/_r
    start_server() {
        OCTANE_MAX_EXECUTION_TIME=$1 pam artisan octane:start --server=pam --host=127.0.0.1 --port=8500 --workers=2 >> /tmp/server.log 2>&1 &
        until curl -fs -o /dev/null $U/hello; do sleep 0.3; done
    }
    start_server 2
    echo "pam: $(pam --version) memory_limit=$(pam -r "echo ini_get(\"memory_limit\");")"

    echo "timeout: $(curl -s -o /dev/null -w "status=%{http_code} seconds=%{time_total}" $U/sleep/6000) (octane.max_execution_time=2, handler sleeps 6 s)"
    ok=0; for i in $(seq 1 20); do [ "$(curl -s -o /dev/null -w "%{http_code}" $U/hello)" = 200 ] && ok=$((ok + 1)); done
    echo "after timeout: $ok/20 requests 200"
    sent=""; for i in 1 2 3; do sent="$sent $(curl -s -o /dev/null -w "%{http_code}" $U/send)"; done
    echo "response()->send() (raw HTTP/ status line):$sent"
    head -c $((100 * 1048576)) /dev/urandom > /data/upload.bin
    touch /tmp/upload.start
    status=$(curl -s -o /dev/null -w "status=%{http_code} seconds=%{time_total}" -F file=@/data/upload.bin $U/upload-sleep/6000)
    rm -f /data/upload.bin
    left=1; for i in $(seq 1 50); do left=$(find /tmp -maxdepth 1 -name "php*" -newer /tmp/upload.start | wc -l); [ "$left" = 0 ] && break; sleep 0.2; done
    echo "timeout during a 100 MB upload: $status, temp_files_left=$left"
    timeout 30 pam artisan octane:stop --server=pam >/dev/null || true
    sleep 2
    start_server 30

    for mb in 100 1024; do
        # The test file lives in a tmpfs (/data), only the PHP upload temp file uses the disk.
        head -c $((mb * 1048576)) /dev/urandom > /data/upload.bin
        expected=$(sha256sum /data/upload.bin | cut -d" " -f1)
        touch /tmp/upload.start
        start=$(date +%s%N)
        body=$(curl -s -F file=@/data/upload.bin $U/upload)
        end=$(date +%s%N)
        rm -f /data/upload.bin
        pid=$(echo "$body" | sed -n "s/.*\"pid\":\([0-9]*\).*/\1/p")
        hwm=$(awk "/VmHWM/{print \$2}" /proc/${pid:-0}/status 2>/dev/null); hwm=${hwm:-0}
        php_peak=$(echo "$body" | sed -n "s/.*\"php_peak_bytes\":\([0-9]*\).*/\1/p")
        php_peak=${php_peak:-0}; [ -n "$pid" ] || echo "upload ${mb} MB failed: $(echo "$body" | head -c 300)"
        sha=$(echo "$body" | sed -n "s/.*\"sha256\":\"\([0-9a-f]*\)\".*/\1/p")
        moved=$(echo "$body" | sed -n "s/.*\"moved_sha256\":\"\([0-9a-f]*\)\".*/\1/p")
        echo "upload ${mb} MB: sha256 $([ "$sha" = "$expected" ] && echo match || echo MISMATCH), move() sha256 $([ "$moved" = "$expected" ] && echo match || echo MISMATCH), ms=$(((end - start) / 1000000)), php_peak_mib=$((php_peak / 1048576)), worker_peak_rss_mib=$((hwm / 1024)), temp_files_left=$(find /tmp -maxdepth 1 -name "php*" -newer /tmp/upload.start | wc -l)"
    done
    timeout 30 pam artisan octane:stop --server=pam >/dev/null || true
    echo "--- server log"; grep -v "^\s*$" /tmp/server.log | tail -20
' 2>&1 | tee "$OUT/behavior.txt"
docker_run "$IMAGE_PHP" php artisan optimize -q
