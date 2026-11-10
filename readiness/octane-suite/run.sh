#!/usr/bin/env bash
# laravel/octane's own test suite, from the push-in/octane 2.x-pam branch, on
# PAM's PHP; then the same suite with every Octane request and response routed
# through Laravel\Octane\Pam\PamClient (PamFakeClient) and cross-checked.
#
#   OCTANE_SRC=/path/to/octane-checkout  use a local checkout instead of cloning
#   PAM=/path/to/pam                     PAM binary (default: pam on PATH)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
PAM="${PAM:-pam}"
OUT="${OUT:-$ROOT/results/$(date +%Y-%m-%d)/octane-suite}"
WORK="${WORK:-${TMPDIR:-/tmp}/octane-benchmarks-suite}"
mkdir -p "$OUT" "$WORK"

if [ -n "${OCTANE_SRC:-}" ]; then
    SRC="$WORK/octane"; rm -rf "$SRC"; git clone -q "$OCTANE_SRC" "$SRC"
    git -C "$SRC" checkout -q "$(git -C "$OCTANE_SRC" rev-parse HEAD)"
else
    SRC="$WORK/octane"; rm -rf "$SRC"
    git clone -q --depth 1 -b 2.x-pam https://github.com/push-in/octane "$SRC"
fi
cd "$SRC"
git rev-parse HEAD > "$OUT/octane-commit.txt"
"$PAM" --version > "$OUT/pam-version.txt"
"$PAM" -r 'echo PHP_VERSION;' > "$OUT/php-version.txt"

"$PAM" composer update --prefer-dist --no-interaction --no-progress -q

# The adapter: PamFakeClient, its bootstrap, and one hook in TestCase.
mkdir -p tests/PamReadiness
cp "$HERE/adapter/PamFakeClient.php" "$HERE/adapter/bootstrap.php" tests/PamReadiness/
python3 - <<'PY'
case = open("tests/TestCase.php").read()
hook = "getenv('OCTANE_DRIVER') === 'pam' ? new \\Laravel\\Octane\\Tests\\PamReadiness\\PamFakeClient($requests) : new FakeClient($requests)"
assert "new FakeClient($requests)" in case
open("tests/TestCase.php", "w").write(case.replace("new FakeClient($requests)", hook, 1))
PY

echo "==> upstream suite on PAM's PHP $(cat "$OUT/php-version.txt")"
"$PAM" vendor/bin/phpunit --log-junit "$OUT/upstream.xml" > "$OUT/upstream.txt" 2>&1 || true
tail -3 "$OUT/upstream.txt"
echo "==> upstream suite with every request and response through PamClient"
OCTANE_DRIVER=pam PAM_OCTANE_MISMATCH_REPORT="$OUT/pam-crosscheck.json" \
    "$PAM" vendor/bin/phpunit --bootstrap tests/PamReadiness/bootstrap.php --log-junit "$OUT/pam-driver.xml" \
    > "$OUT/pam-driver.txt" 2>&1 || true
tail -3 "$OUT/pam-driver.txt"
echo "==> upstream suite on system PHP $(php -r 'echo PHP_VERSION;' 2>/dev/null || echo n/a)"
if command -v php >/dev/null; then
    php vendor/bin/phpunit --log-junit "$OUT/system-php.xml" > "$OUT/system-php.txt" 2>&1 || true
    tail -3 "$OUT/system-php.txt"
fi
cd "$ROOT"
[ "${KEEP_WORK:-0}" = 1 ] || rm -rf "$WORK"
python3 "$HERE/summarize.py" "$OUT"
