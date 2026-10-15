# PHP & NGINX Startup Script

This script initializes PHP-FPM and NGINX for the container in a robust and configurable way.

## Features

- Reads PHP version from the `PHP_VERSION` environment variable
- Starts PHP-FPM with configurable `php.ini` and `php-fpm.conf`
- Starts NGINX with configurable config (`NGINX_CONF`) and prefix (`NGINX_PREFIX`)
- Supervises PHP-FPM: if it dies, or stays running but stops accepting connections on its
  socket, the cause is printed to the console and PHP-FPM is restarted automatically
- Colorized, structured output for readability
- Robust execution with `set -euo pipefail` and error trapping
- Fully configurable via environment variables

## Configuration

| Env Variable      | Default                              | Description                                  |
|-------------------|--------------------------------------|----------------------------------------------|
| `PHP_VERSION`     | `8.4`                                | PHP version to run (used in `php-fpm{VERSION}`) |
| `PHP_INI`         | `/home/container/php/php.ini`        | Path to the `php.ini` file                  |
| `PHP_FPM_CONF`    | `/home/container/php/php-fpm.conf`   | Path to the PHP-FPM configuration file       |
| `NGINX_CONF`      | `/home/container/nginx/nginx.conf`   | Path to the NGINX config file                |
| `NGINX_PREFIX`    | `/home/container`                    | Directory prefix for NGINX (`-p` flag)      |
| `PHP_FPM_MAX_RESTARTS` | `5`                             | PHP-FPM crashes allowed within the window before the server stops |
| `PHP_FPM_RESTART_WINDOW` | `300`                         | Window in seconds for counting PHP-FPM crashes |
| `PHP_FPM_HEALTHCHECK_INTERVAL` | `30`                    | Seconds between connection checks on PHP-FPM's listen address; `0` disables |
| `PHP_FPM_LISTEN`  | first pool's `listen`                | Address to check (socket path or `host:port`) |

## PHP-FPM watchdog

PHP-FPM runs in the foreground under this script instead of being daemonized and forgotten.
Previously, if the PHP-FPM master died, nginx kept running and every PHP request failed with
`connect() to unix:/home/container/tmp/php-fpm.sock failed (111: Connection refused)` until
the server was restarted manually. Now the console shows a line such as
`[Watchdog] PHP-FPM killed by SIGKILL (...)` followed by `[Watchdog] PHP-FPM restarted`.

Error 111 also occurs while PHP-FPM is still running if its socket file is deleted and
recreated or moved by something outside PHP-FPM: the path then refers to a new file
with no listener. The watchdog therefore connects to the listen address every
`PHP_FPM_HEALTHCHECK_INTERVAL` seconds. After two consecutive refusals (or a missing socket)
it logs `[Watchdog] PHP-FPM is running (PID: ...) but ...: connection refused`, prints
the socket file details, and restarts PHP-FPM. A busy pool that is slow to accept
connections is not treated as a failure. Only the first pool is checked. Workers left behind by a killed master are
removed so the socket can be reopened. If PHP-FPM crashes more than `PHP_FPM_MAX_RESTARTS`
times within `PHP_FPM_RESTART_WINDOW` seconds, nginx is stopped and the server exits with an
error so the panel reports it. If nginx exits, PHP-FPM is stopped and the server exits with
nginx's status.

Which message appears identifies the cause: an exit/signal message means the PHP-FPM
process died (a `SIGKILL` leaves nothing in `logs/php-fpm.log`; check `dmesg` on the host);
the "is running ... but" message means the socket file under `/home/container/tmp` was
replaced while PHP-FPM kept running. On Unraid, make sure the share holding the Pelican
volumes is not moved between cache and array by the mover or touched by backup/cleanup
jobs, or set `listen` in `php/pool.d/www.conf` and `fastcgi_pass` in `nginx/conf.d/*.conf`
to a TCP address such as `127.0.0.1:9000`.

## Script Details

- The script expects `PHP_VERSION` to be provided. It defaults to `8.4` if unset.
- Uses strict shell flags and a trap for error reporting.
- Color codes and header functions improve readability and maintainability.

## Example Egg JSON Variables

```json
"variables": [
  {
    "name": "PHP Version",
    "env_variable": "PHP_VERSION",
    "default_value": "8.4",
    "description": "PHP version to use",
    "required": false
  },
  {
    "name": "PHP INI Path",
    "env_variable": "PHP_INI",
    "default_value": "/home/container/php/php.ini",
    "description": "Path to php.ini",
    "required": false
  },
  {
    "name": "PHP-FPM Config Path",
    "env_variable": "PHP_FPM_CONF",
    "default_value": "/home/container/php/php-fpm.conf",
    "description": "Path to PHP-FPM config",
    "required": false
  },
  {
    "name": "NGINX Config Path",
    "env_variable": "NGINX_CONF",
    "default_value": "/home/container/nginx/nginx.conf",
    "description": "Path to NGINX config",
    "required": false
  }
]
```

