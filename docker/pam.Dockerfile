FROM ubuntu:24.04
ARG PAM_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl tzdata wrk procps \
    && rm -rf /var/lib/apt/lists/*
ENV PAM_INSTALL_DIR=/opt/pam PAM_BIN_DIR=/usr/local/bin
# PAM's official install script verifies the release checksum.
RUN curl --proto '=https' --tlsv1.2 -fsSL \
      "https://github.com/push-in/pam/releases/download/v${PAM_VERSION}/install.sh" -o /tmp/install.sh \
    && PAM_VERSION="v${PAM_VERSION}" sh /tmp/install.sh && rm /tmp/install.sh
COPY bench.ini /tmp/bench.ini
RUN mv /tmp/bench.ini "$(dirname "$(pam -r 'echo php_ini_loaded_file();')")/conf.d/99-bench.ini" \
    && pam -r 'echo PHP_VERSION, " jit=", ini_get("opcache.jit"), PHP_EOL;' && pam --version
WORKDIR /app
