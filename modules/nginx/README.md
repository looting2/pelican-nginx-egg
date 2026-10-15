# PHP & NGINX Startup Script

This script initializes PHP-FPM and NGINX for the container in a robust and configurable way.

## Features

- Reads PHP version from the `PHP_VERSION` environment variable
- Starts PHP-FPM with configurable `php.ini` and `php-fpm.conf`
- Starts NGINX with configurable config (`NGINX_CONF`) and prefix (`NGINX_PREFIX`)
- Supervises PHP-FPM: if it dies (for example killed by the out-of-memory killer), the
  exit status is printed to the console and PHP-FPM is restarted automatically
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

## PHP-FPM watchdog

PHP-FPM runs in the foreground under this script instead of being daemonized and forgotten.
Previously, if the PHP-FPM master died, nginx kept running and every PHP request failed with
`connect() to unix:/home/container/tmp/php-fpm.sock failed (111: Connection refused)` until
the server was restarted manually. Now the console shows a line such as
`[Watchdog] PHP-FPM killed by SIGKILL (often the out-of-memory killer or container memory limit)`
followed by `[Watchdog] PHP-FPM restarted`. Workers left behind by a killed master are
removed so the socket can be reopened. If PHP-FPM crashes more than `PHP_FPM_MAX_RESTARTS`
times within `PHP_FPM_RESTART_WINDOW` seconds, nginx is stopped and the server exits with an
error so the panel reports it. If nginx exits, PHP-FPM is stopped and the server exits with
nginx's status.

A `SIGKILL` leaves nothing in `logs/php-fpm.log`; check the server's memory limit in the
panel and the host kernel log (`dmesg | grep -i oom`) to confirm an out-of-memory kill.

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

