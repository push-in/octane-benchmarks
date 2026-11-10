# Swoole and RoadRunner share the official PHP image; it also provisions the app.
ARG PHP_IMAGE
FROM ${PHP_IMAGE}
ARG SWOOLE_VERSION
ARG ROADRUNNER_VERSION
ARG COMPOSER_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends libsqlite3-dev libbrotli-dev libssl-dev curl git unzip \
    && docker-php-ext-install -j4 pcntl sockets pdo_sqlite \
    && pecl install "swoole-${SWOOLE_VERSION}" && docker-php-ext-enable swoole \
    && curl -fsSL "https://github.com/roadrunner-server/roadrunner/releases/download/v${ROADRUNNER_VERSION}/roadrunner-${ROADRUNNER_VERSION}-linux-amd64.tar.gz" \
      | tar -xz -C /tmp && mv /tmp/roadrunner-*/rr /usr/local/bin/rr \
    && curl -fsSL -o /usr/local/bin/composer "https://getcomposer.org/download/${COMPOSER_VERSION}/composer.phar" \
    && chmod +x /usr/local/bin/composer \
    && rm -rf /tmp/* /var/lib/apt/lists/*
COPY bench.ini /usr/local/etc/php/conf.d/zz-bench.ini
RUN php -m | grep -E 'swoole|pdo_sqlite|Zend OPcache' && rr --version && composer --version \
    && php -r 'echo PHP_VERSION, " jit=", ini_get("opcache.jit"), PHP_EOL;'
WORKDIR /app
