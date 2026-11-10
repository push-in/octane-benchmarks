#!/usr/bin/env bash
# One Laravel app for every server: laravel/laravel, Laravel $LARAVEL_VERSION,
# Octane from push-in/octane at $OCTANE_REF, RoadRunner's PHP packages,
# the routes in app/, SQLite with 100 users, APP_ENV=production, `optimize`.
source "$(dirname "$0")/lib.sh"
if [ -f "$APP/vendor/autoload.php" ] && [ -f "$APP/routes/bench.php" ]; then
    log "app already provisioned at $APP"; exit 0
fi
rm -rf "$APP"; mkdir -p "$APP"
log "provisioning $APP"
docker_run -e COMPOSER_HOME=/tmp/composer \
    -e OCTANE_REPO_JSON="{\"type\": \"vcs\", \"url\": \"$OCTANE_REPOSITORY\", \"no-api\": true}" "$IMAGE_PHP" sh -ec "
    composer create-project --no-interaction --prefer-dist --no-scripts laravel/laravel /tmp/skeleton >/dev/null 2>&1
    cp -a /tmp/skeleton/. '$APP'/
    composer config repositories.octane \"\$OCTANE_REPO_JSON\"
    composer require --no-interaction -W --no-scripts 'laravel/framework:$LARAVEL_VERSION' \
        'laravel/octane:dev-2.x-pam#$OCTANE_REF' spiral/roadrunner-http spiral/roadrunner-cli >/dev/null 2>&1
    composer run-script post-autoload-dump >/dev/null
    cp .env.example .env && php artisan key:generate -q
"
cp -R "$ROOT/app/." "$APP/"
(
    cd "$APP"
    # Probe routes without the web middleware group.
    sed -i "s#health: '/up',#health: '/up',\n        then: fn () => \\\\Illuminate\\\\Support\\\\Facades\\\\Route::group([], base_path('routes/bench.php')),#" bootstrap/app.php
    grep -q "routes/bench.php" bootstrap/app.php
    sed -i 's/^APP_ENV=.*/APP_ENV=production/; s/^APP_DEBUG=.*/APP_DEBUG=false/; s/^LOG_LEVEL=.*/LOG_LEVEL=error/; s/^DB_CONNECTION=.*/DB_CONNECTION=sqlite/; s/^SESSION_DRIVER=.*/SESSION_DRIVER=file/; s/^CACHE_STORE=.*/CACHE_STORE=file/' .env
    touch database/database.sqlite .rr.yaml
)
docker_run "$IMAGE_PHP" sh -ec "
    php artisan vendor:publish --tag=octane-config -q
    sed -i \"s/'max_execution_time' => 30,/'max_execution_time' => (int) env('OCTANE_MAX_EXECUTION_TIME', 30),/\" config/octane.php
    php artisan migrate --force -q
    php artisan tinker --execute='App\\Models\\User::factory()->count(100)->create();' >/dev/null
    php artisan optimize -q
    php artisan --version
    composer show laravel/octane | grep -E '^(versions|source)'
"
