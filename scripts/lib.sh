# shellcheck shell=bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
set -a; . "$ROOT/versions.env"; set +a
WORK="${WORK:-$ROOT/work}"
APP="$WORK/app"
PORT="${PORT:-8400}"
RESULTS="${RESULTS:-$ROOT/results/$(date +%Y-%m-%d)}"
IMAGE_PAM="octane-bench/pam:$PAM_VERSION"
IMAGE_FRANKENPHP="octane-bench/frankenphp:$FRANKENPHP_VERSION"
IMAGE_PHP="octane-bench/php-octane:$SWOOLE_VERSION-$ROADRUNNER_VERSION"
mkdir -p "$WORK" "$RESULTS"

log() { printf '\033[1m==> %s\033[0m\n' "$*" >&2; }

# The app lives at the same path inside and outside the containers, because
# `artisan optimize` caches absolute paths.
docker_run() {
    docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$APP:$APP" -w "$APP" "$@"
}

wait_http() {
    local url="$1" deadline=$((SECONDS + ${2:-90}))
    until curl -fsS -o /dev/null "$url" 2>/dev/null; do
        [ $SECONDS -lt $deadline ] || { log "timeout waiting for $url"; return 1; }
        sleep 0.3
    done
}
