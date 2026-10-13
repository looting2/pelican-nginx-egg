#!/usr/bin/env bash
set -euo pipefail
trap 'echo -e "${YELLOW}[Startup] Error on line $LINENO${NC}"' ERR

# Color definitions
RED='\033[0;31m'
BLUE='\033[0;34m'; BOLD_BLUE='\033[1;34m'
WHITE='\033[0;37m'; GREEN='\033[0;32m'
YELLOW='\033[0;33m'; CYAN='\033[1;36m'
UNDERLINE='\033[4m'; NC='\033[0m'

# Header function
header() {
  echo -e "${BLUE}───────────────────────────────────────────────${NC}"
  echo -e "${BOLD_BLUE}$1${NC}"
}

# Configurable paths/files via env vars with defaults
PHP_VERSION="${PHP_VERSION:-${IMAGE_PHP_VERSION:-8.4}}"
if [[ -n "${IMAGE_PHP_VERSION:-}" && "$PHP_VERSION" != "$IMAGE_PHP_VERSION" ]]; then
  echo "[Startup] PHP_VERSION must match image version $IMAGE_PHP_VERSION." >&2
  exit 1
fi
PHP_INI="${PHP_INI:-/home/container/php/php.ini}"
PHP_FPM_CONF="${PHP_FPM_CONF:-/home/container/php/php-fpm.conf}"
NGINX_CONF="${NGINX_CONF:-/home/container/nginx/nginx.conf}"
NGINX_PREFIX="${NGINX_PREFIX:-/home/container}"

# Locate php-fpm binary for the desired version
if command -v "php-fpm${PHP_VERSION}" >/dev/null 2>&1; then
  PHP_FPM_BIN="php-fpm${PHP_VERSION}"
elif command -v php-fpm >/dev/null 2>&1; then
  PHP_FPM_BIN=php-fpm
else
  echo -e "${RED}[Startup] ERROR: php-fpm${PHP_VERSION} not found; this may indicate a version mismatch between your Docker image and the PHP_VERSION variable (${PHP_VERSION}).${NC}"
  exit 1
fi

# Validate both configurations before starting either service.
"$PHP_FPM_BIN" -c "$PHP_INI" --fpm-config "$PHP_FPM_CONF" --test
nginx -t -c "$NGINX_CONF" -p "$NGINX_PREFIX" -e stderr

php_pid=""
nginx_pid=""
stop_services() {
  trap - EXIT
  [[ -z "$php_pid" ]] || kill -TERM "$php_pid" 2>/dev/null || true
  [[ -z "$nginx_pid" ]] || kill -TERM "$nginx_pid" 2>/dev/null || true
  [[ -z "$php_pid" ]] || wait "$php_pid" 2>/dev/null || true
  [[ -z "$nginx_pid" ]] || wait "$nginx_pid" 2>/dev/null || true
}
trap stop_services EXIT
trap 'exit 0' TERM INT

# Keep the FPM master attached so its exit cannot leave Nginx serving 502s.
header "[Startup] Starting PHP-FPM"
echo -e "${WHITE}[Startup] Launching ${PHP_FPM_BIN} (PHP ${PHP_VERSION})${NC}"
"$PHP_FPM_BIN" \
  -c "$PHP_INI" \
  --fpm-config "$PHP_FPM_CONF" \
  --nodaemonize --force-stderr &
php_pid=$!

# Brief pause
sleep 1
if ! kill -0 "$php_pid" 2>/dev/null; then
  status=0
  wait "$php_pid" || status=$?
  echo "[Startup] ERROR: PHP-FPM exited during startup (status $status); check its console output and logs/php-fpm.log." >&2
  [[ "$status" -ne 0 ]] || status=1
  exit "$status"
fi

# Copyright footer
echo -e " "
echo -e "\033[0;34m───────────────────────────────────────────────\033[0m"
echo -e "\033[1;36mOriginal runtime © 2023-2026 Ym0T; independently maintained by looting2\033[0m"
echo -e "\033[1;36mScript: \033[4;34mhttps://github.com/looting2/pelican-nginx-egg\033[0m"
echo -e "\033[1;36mLicensed under the MIT License.\033[0m"
echo -e "\033[1;36mSee the LICENSE file for details.\033[0m"
echo -e "\033[0;34m───────────────────────────────────────────────\033[0m"

# Start NGINX
nginx -c "$NGINX_CONF" -p "$NGINX_PREFIX" -e stderr &
nginx_pid=$!
echo -e "${GREEN}[Startup] Services successfully launched!${NC}"

status=0
while kill -0 "$php_pid" 2>/dev/null && kill -0 "$nginx_pid" 2>/dev/null; do
  sleep 0.5
done
if ! kill -0 "$php_pid" 2>/dev/null; then
  service="PHP-FPM"
  wait "$php_pid" || status=$?
else
  service="Nginx"
  wait "$nginx_pid" || status=$?
fi
echo "[Startup] ERROR: $service exited (status $status); stopping both services. Check console output and logs/php-fpm.log." >&2
[[ "$status" -ne 0 ]] || status=1
exit "$status"
