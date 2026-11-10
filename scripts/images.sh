#!/usr/bin/env bash
# Builds the three images with the exact versions in versions.env.
source "$(dirname "$0")/lib.sh"
cd "$ROOT/docker"
docker build -q -t "$IMAGE_PAM" --build-arg PAM_VERSION="$PAM_VERSION" -f pam.Dockerfile . >/dev/null
docker build -q -t "$IMAGE_FRANKENPHP" --build-arg FRANKENPHP_VERSION="$FRANKENPHP_VERSION" -f frankenphp.Dockerfile . >/dev/null
docker build -q -t "$IMAGE_PHP" --build-arg PHP_IMAGE="$PHP_IMAGE" --build-arg SWOOLE_VERSION="$SWOOLE_VERSION" \
    --build-arg ROADRUNNER_VERSION="$ROADRUNNER_VERSION" --build-arg COMPOSER_VERSION="$COMPOSER_VERSION" \
    -f php-octane.Dockerfile . >/dev/null
docker images --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}' | grep '^octane-bench/'
