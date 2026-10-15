FROM debian:bookworm-slim

LABEL org.opencontainers.image.source="https://github.com/looting2/pelican-nginx-egg" \
      org.opencontainers.image.licenses="MIT"

ARG PHP_VERSION=8.4
ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/container USER=container \
    IMAGE_PHP_VERSION=${PHP_VERSION}

RUN set -eux; \
    case "$PHP_VERSION" in 8.2|8.3|8.4|8.5) ;; *) exit 1;; esac; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl gnupg git nginx \
        unzip tar python3 certbot openssl openssh-client sshpass procps msmtp-mta; \
    test -x /usr/sbin/sendmail; \
    curl -fsSL https://packages.sury.org/php/apt.gpg -o /usr/share/keyrings/sury-php.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/sury-php.gpg] https://packages.sury.org/php/ bookworm main" > /etc/apt/sources.list.d/php.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        php${PHP_VERSION}-fpm php${PHP_VERSION}-cli php${PHP_VERSION}-common \
        php${PHP_VERSION}-mysql php${PHP_VERSION}-xml php${PHP_VERSION}-bcmath \
        php${PHP_VERSION}-curl php${PHP_VERSION}-mbstring php${PHP_VERSION}-gd \
        php${PHP_VERSION}-gmp php${PHP_VERSION}-intl php${PHP_VERSION}-ldap \
        php${PHP_VERSION}-odbc php${PHP_VERSION}-pgsql php${PHP_VERSION}-sqlite3 \
        php${PHP_VERSION}-soap php${PHP_VERSION}-zip php${PHP_VERSION}-dev; \
    for extension in sybase psr igbinary imagick imap mongodb msgpack pcov ps pspell \
        mailparse inotify maxminddb protobuf memcache memcached opcache; do \
        package="php${PHP_VERSION}-${extension}"; \
        if apt-cache show "$package" > /dev/null 2>&1; then \
            apt-get install -y --no-install-recommends "$package"; \
        else \
            echo "Optional extension unavailable: $package"; \
        fi; \
    done; \
    update-alternatives --set php /usr/bin/php${PHP_VERSION}; \
    command -v php-fpm${PHP_VERSION}; \
    curl -fsSL https://getcomposer.org/download/latest-stable/composer.phar -o /usr/local/bin/composer; \
    checksum="$(curl -fsSL https://getcomposer.org/download/latest-stable/composer.phar.sha256)"; \
    echo "$checksum  /usr/local/bin/composer" | sha256sum -c -; \
    chmod +x /usr/local/bin/composer; \
    case "$TARGETARCH" in amd64|arm64) arch="$TARGETARCH";; *) arch="$(dpkg --print-architecture)";; esac; \
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}" -o /usr/local/bin/cloudflared; \
    chmod +x /usr/local/bin/cloudflared; \
    rm -rf /var/lib/apt/lists/*

# ionCube is optional because loaders can lag behind new PHP releases.
RUN set -eu; \
    case "$(dpkg --print-architecture)" in amd64) arch=x86-64;; arm64) arch=aarch64;; *) exit 1;; esac; \
    cd /usr/local/src; \
    if curl -fsSL "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_${arch}.tar.gz" -o ioncube.tar.gz; then \
        if tar -xzf ioncube.tar.gz "ioncube/ioncube_loader_lin_${PHP_VERSION}.so"; then \
            extension_dir="$(php -r 'echo ini_get("extension_dir");')"; \
            cp "ioncube/ioncube_loader_lin_${PHP_VERSION}.so" "$extension_dir/"; \
            for sapi in cli fpm; do \
                echo "zend_extension=${extension_dir}/ioncube_loader_lin_${PHP_VERSION}.so" > "/etc/php/${PHP_VERSION}/${sapi}/conf.d/00-ioncube.ini"; \
            done; \
        else echo "ionCube loader unavailable for PHP $PHP_VERSION"; fi; \
    else echo "ionCube download unavailable; skipping optional loader"; fi; \
    rm -rf ioncube ioncube.tar.gz

RUN useradd --create-home --home-dir /home/container --shell /bin/bash container
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
USER container
WORKDIR /home/container
STOPSIGNAL SIGINT
ENTRYPOINT ["/entrypoint.sh"]
