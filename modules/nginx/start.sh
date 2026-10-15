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

# Watchdog tuning: give up after PHP_FPM_MAX_RESTARTS crashes within PHP_FPM_RESTART_WINDOW seconds
PHP_FPM_MAX_RESTARTS="${PHP_FPM_MAX_RESTARTS:-5}"
PHP_FPM_RESTART_WINDOW="${PHP_FPM_RESTART_WINDOW:-300}"
[[ "$PHP_FPM_MAX_RESTARTS" =~ ^[0-9]+$ ]] || PHP_FPM_MAX_RESTARTS=5
[[ "$PHP_FPM_RESTART_WINDOW" =~ ^[0-9]+$ ]] || PHP_FPM_RESTART_WINDOW=300

log() { echo -e "$1 [$(date '+%Y-%m-%d %H:%M:%S')]${NC}"; }

# Describe an exit status, naming the signal when a process was killed.
describe_exit() {
  local status="$1" signal
  if ((status > 128)) && signal="$(kill -l "$((status - 128))" 2>/dev/null)"; then
    if [[ "$signal" == KILL ]]; then
      echo "killed by SIGKILL (often the out-of-memory killer or container memory limit)"
    else
      echo "killed by SIG${signal}"
    fi
  else
    echo "exited with status ${status}"
  fi
}

# PHP-FPM runs in the foreground under this script so a crash is detected and restarted
# instead of leaving nginx with a dead socket (502 / "Connection refused").
# It gets its own process group so workers orphaned by a killed master can be removed;
# otherwise they keep the socket and block the restart.
start_php_fpm() {
  setsid "$PHP_FPM_BIN" -c "$PHP_INI" --fpm-config "$PHP_FPM_CONF" --nodaemonize &
  PHP_FPM_PID=$!
}
stop_php_fpm_workers() { kill -KILL -- "-$PHP_FPM_PID" 2>/dev/null; }

# Start PHP-FPM
header "[Startup] Starting PHP-FPM"
echo -e "${WHITE}[Startup] Launching ${PHP_FPM_BIN} (PHP ${PHP_VERSION})${NC}"
start_php_fpm
sleep 1
if ! kill -0 "$PHP_FPM_PID" 2>/dev/null; then
  echo -e "${RED}[Startup] ERROR: Failed to launch ${PHP_FPM_BIN}. Please check that your PHP_VERSION matches the installed php-fpm binary and review logs/php-fpm.log.${NC}"
  exit 1
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
NGINX_PID=$!

# Supervision: errors are handled explicitly from here on.
set +e
trap - ERR
stopping=0
stop_services() {
  stopping=1
  kill -TERM "$NGINX_PID" "$PHP_FPM_PID" 2>/dev/null
}
trap stop_services INT TERM QUIT HUP

# Success message
echo -e "${GREEN}[Startup] Services successfully launched!${NC}"

restart_times=()
while true; do
  exited_pid=""
  wait -n -p exited_pid "$NGINX_PID" "$PHP_FPM_PID"
  status=$?
  if ((stopping)); then
    wait "$NGINX_PID" "$PHP_FPM_PID" 2>/dev/null
    stop_php_fpm_workers
    log "${WHITE}[Shutdown] nginx and PHP-FPM stopped"
    exit 0
  fi
  # A trapped signal interrupts wait without any child exiting.
  [[ -n "$exited_pid" ]] || continue

  if [[ "$exited_pid" == "$NGINX_PID" ]]; then
    log "${RED}[Watchdog] nginx $(describe_exit "$status"); stopping PHP-FPM"
    kill -TERM "$PHP_FPM_PID" 2>/dev/null
    wait "$PHP_FPM_PID" 2>/dev/null
    stop_php_fpm_workers
    exit "$status"
  fi

  log "${RED}[Watchdog] PHP-FPM $(describe_exit "$status")"
  stop_php_fpm_workers
  now=$SECONDS
  recent=()
  for time in "${restart_times[@]}"; do
    ((now - time < PHP_FPM_RESTART_WINDOW)) && recent+=("$time")
  done
  restart_times=("${recent[@]}" "$now")
  if ((${#restart_times[@]} > PHP_FPM_MAX_RESTARTS)); then
    log "${RED}[Watchdog] PHP-FPM crashed ${#restart_times[@]} times within ${PHP_FPM_RESTART_WINDOW}s; stopping the server. Check logs/php-fpm.log and the container memory limit"
    kill -TERM "$NGINX_PID" 2>/dev/null
    wait "$NGINX_PID" 2>/dev/null
    exit 1
  fi
  sleep 1
  start_php_fpm
  log "${YELLOW}[Watchdog] PHP-FPM restarted (PID: ${PHP_FPM_PID})"
done
