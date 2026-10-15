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
# Seconds between checks that PHP-FPM accepts connections; 0 disables the check.
PHP_FPM_HEALTHCHECK_INTERVAL="${PHP_FPM_HEALTHCHECK_INTERVAL:-30}"
[[ "$PHP_FPM_HEALTHCHECK_INTERVAL" =~ ^[0-9]+$ ]] || PHP_FPM_HEALTHCHECK_INTERVAL=30

log() { echo -e "$1 [$(date '+%Y-%m-%d %H:%M:%S')]${NC}"; }

# Describe an exit status, naming the signal when a process was killed.
describe_exit() {
  local status="$1" signal
  if ((status > 128)) && signal="$(kill -l "$((status - 128))" 2>/dev/null)"; then
    if [[ "$signal" == KILL ]]; then
      echo "killed by SIGKILL (by the out-of-memory killer or another process; PHP-FPM cannot log this)"
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

# Listen address of the first pool: PHP_FPM_LISTEN, or read from PHP_FPM_CONF and its include.
php_fpm_listen() {
  local include files=("$PHP_FPM_CONF") file
  if [[ -n "${PHP_FPM_LISTEN:-}" ]]; then
    echo "$PHP_FPM_LISTEN"
    return
  fi
  include="$(sed -n 's/^[[:space:]]*include[[:space:]]*=[[:space:]]*//p' "$PHP_FPM_CONF" 2>/dev/null | tail -n 1)"
  if [[ -n "$include" ]]; then
    while IFS= read -r file; do files+=("$file"); done < <(compgen -G "$include" | sort)
  fi
  sed -n 's/^[[:space:]]*listen[[:space:]]*=[[:space:]]*//p' "${files[@]}" 2>/dev/null |
    head -n 1 | tr -d "\"'" | sed 's/[[:space:]]*$//'
}

# Prints a reason and fails only when PHP-FPM refuses connections; a busy pool (timeout) passes.
php_fpm_unreachable() {
  python3 - "$1" <<'PY'
import socket, sys
address = sys.argv[1]
if address.startswith("/"):
    family, target = socket.AF_UNIX, address
else:
    host, _, port = address.rpartition(":")
    family, target = socket.AF_INET6 if ":" in host else socket.AF_INET, (host.strip("[]") or "127.0.0.1", int(port))
connection = socket.socket(family)
connection.settimeout(5)
try:
    connection.connect(target)
except FileNotFoundError:
    print("socket file is missing")
    sys.exit(0)
except ConnectionRefusedError:
    print("connection refused (socket file exists but nothing is listening on it)" if family == socket.AF_UNIX else "connection refused")
    sys.exit(0)
except OSError:
    pass
sys.exit(1)
PY
}

start_ticker() {
  TICK_PID=""
  ((PHP_FPM_HEALTHCHECK_INTERVAL > 0)) && [[ -n "$PHP_FPM_ADDRESS" ]] || return 0
  sleep "$PHP_FPM_HEALTHCHECK_INTERVAL" &
  TICK_PID=$!
}
stop_ticker() { [[ -z "$TICK_PID" ]] || kill "$TICK_PID" 2>/dev/null; }

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
PHP_FPM_ADDRESS=""
if ((PHP_FPM_HEALTHCHECK_INTERVAL > 0)) && command -v python3 >/dev/null 2>&1; then
  PHP_FPM_ADDRESS="$(php_fpm_listen)"
  [[ "$PHP_FPM_ADDRESS" =~ ^(/.+|.*[0-9])$ ]] || PHP_FPM_ADDRESS=""
fi
start_ticker
stopping=0
stop_services() {
  stopping=1
  kill -TERM "$NGINX_PID" "$PHP_FPM_PID" 2>/dev/null
}
trap stop_services INT TERM QUIT HUP

# Success message
echo -e "${GREEN}[Startup] Services successfully launched!${NC}"

restart_times=()
health_failures=0
while true; do
  exited_pid=""
  wait -n -p exited_pid "$NGINX_PID" "$PHP_FPM_PID" ${TICK_PID:+"$TICK_PID"}
  status=$?
  if ((stopping)); then
    stop_ticker
    kill -TERM "$NGINX_PID" "$PHP_FPM_PID" 2>/dev/null
    wait "$NGINX_PID" "$PHP_FPM_PID" 2>/dev/null
    stop_php_fpm_workers
    log "${WHITE}[Shutdown] nginx and PHP-FPM stopped"
    exit 0
  fi
  # A trapped signal interrupts wait without any child exiting.
  [[ -n "$exited_pid" ]] || continue

  if [[ "$exited_pid" == "$NGINX_PID" ]]; then
    log "${RED}[Watchdog] nginx $(describe_exit "$status"); stopping PHP-FPM"
    stop_ticker
    kill -TERM "$PHP_FPM_PID" 2>/dev/null
    wait "$PHP_FPM_PID" 2>/dev/null
    stop_php_fpm_workers
    exit "$status"
  fi

  if [[ "$exited_pid" == "$TICK_PID" ]]; then
    start_ticker
    if ! reason="$(php_fpm_unreachable "$PHP_FPM_ADDRESS")"; then
      health_failures=0
      continue
    fi
    # Require two consecutive failures so a single transient error does not restart PHP-FPM.
    ((++health_failures >= 2)) || continue
    health_failures=0
    log "${RED}[Watchdog] PHP-FPM is running (PID: ${PHP_FPM_PID}) but ${PHP_FPM_ADDRESS}: ${reason}; restarting PHP-FPM"
    if [[ "$PHP_FPM_ADDRESS" == /* ]]; then
      echo "[Watchdog] Socket details: $(ls -li -- "$PHP_FPM_ADDRESS" 2>&1)"
    fi
    kill -TERM "$PHP_FPM_PID" 2>/dev/null
    wait "$PHP_FPM_PID" 2>/dev/null
  else
    health_failures=0
    log "${RED}[Watchdog] PHP-FPM $(describe_exit "$status")"
  fi
  stop_php_fpm_workers
  now=$SECONDS
  recent=()
  for time in "${restart_times[@]}"; do
    ((now - time < PHP_FPM_RESTART_WINDOW)) && recent+=("$time")
  done
  restart_times=("${recent[@]}" "$now")
  if ((${#restart_times[@]} > PHP_FPM_MAX_RESTARTS)); then
    log "${RED}[Watchdog] PHP-FPM failed ${#restart_times[@]} times within ${PHP_FPM_RESTART_WINDOW}s; stopping the server. Check logs/php-fpm.log"
    stop_ticker
    kill -TERM "$NGINX_PID" 2>/dev/null
    wait "$NGINX_PID" 2>/dev/null
    exit 1
  fi
  sleep 1
  ((stopping)) && continue
  start_php_fpm
  log "${YELLOW}[Watchdog] PHP-FPM restarted (PID: ${PHP_FPM_PID})"
done
