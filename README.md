# Nginx Cloudflare Egg

A versatile **Pelican Panel Egg** featuring Nginx, PHP 8.x, WordPress, Git, Composer, Cronjob, ionCube Loader, Auto-Update, and Cloudflare Tunnel support.

**Fork by Vava22**, originally adapted from [Ym0T's Pterodactyl Nginx Egg](https://github.com/Ym0T/pterodactyl-nginx-egg).

## Features

- 🔄 **Auto-Update**: Automatically checks for and applies updates via Tavuru API
- 🧹 **LogCleaner**: Truncates oversized or old logs without touching temporary/runtime files (dry-run supported)
- 🌱 **Git Module**: Auto `git pull` on restart
- 📦 **Composer Module**: Installs packages from `composer.json` or a fallback variable
- 🔐 **ionCube Loader**: Auto-detected and enabled for encrypted PHP
- 🌐 **Cloudflare Tunnel**: Secure tunnel with token validation
- 🚀 **PHP-NGINX Startup**: Auto-detects PHP-FPM version, runs NGINX in foreground
- 🖥️ **Multi-arch support**: AMD64 & ARM64
- 🎯 **Selectable PHP Versions**:
  - ✅ 8.5
  - ✅ 8.4
  - ☑️ 8.3 (security-only)
  - ☑️ 8.2 (security-only)
  - ❌ 8.1 (EOL)

[PHP Supported Versions](https://www.php.net/supported-versions.php)

## Installation

1. Download the egg file (`egg-pelican-nginx.json`).
2. In your **Pelican Panel**, navigate to **Nests** in the sidebar.
3. Click **Import Egg**.
4. Create a new server and select the **Pelican Nginx** egg.
5. Choose the Docker image matching your desired PHP version.
6. Fill in all required variables, including whether **WordPress** is desired and the PHP version field (must be set explicitly).

## Configuration

| Variable | Default | Description |
| :--- | :--- | :--- |
| `AUTOUPDATE_STATUS` | `1` | Enable (`1`) or disable (`0`) auto-update checks |
| `AUTOUPDATE_FORCE` | `1` | Automatically apply updates (`1`) or just check (`0`) |
| `PHP_VERSION` | - | **Required**. Must match the Docker image tag (e.g., `8.4`) |
| `WORDPRESS` | `0` | Set to `1` to install WordPress automatically |
| `LOGCLEANER_STATUS` | `1` | Enable (`1`/`true`) safe startup log cleanup; disable with `0`/`false` |
| `CLOUDFLARED_STATUS` | `0` | Enable Cloudflare Tunnel (`1`) |
| `CLOUDFLARED_TOKEN` | - | Your Cloudflare Tunnel token (starts with `ey...`) |

### Safe Log Cleanup

The egg startup command includes a safe cleaner before launching the upstream
modules. It never cleans `tmp` or `/tmp`, preserving PHP-FPM sockets, PID files,
PHP sessions, and other runtime data. Only regular `*.log` files inside the
server's `logs` directory are eligible; symlinked files and directories are not
followed. Eligible logs are truncated in place rather than deleted, preserving
open file handles and reclaiming their existing disk space.

Cleanup runs **at startup only**, not periodically. Defaults are `MAX_SIZE_MB=10`
and `MAX_AGE_DAYS=30`; a log is eligible if it exceeds either threshold. Set
`DRY_RUN=true` or `DRY_RUN=1` to preview cleanup without changing files. Optional
`LOG_DIR` must resolve to the server's `logs` directory or a subdirectory within it.
These optional settings can be supplied as environment variables. Archived files
that do not end in `.log` are not cleaned. Continuous log growth still requires
separate log rotation.

The wrapper disables the upstream LogCleaner for the rest of startup, including
after upstream auto-updates. Other modules and their settings remain unchanged.

#### Testing on an existing server (no reinstall required)

1. Back up your current startup command and logs you want to retain.
2. Upload this repository's `safe-start.sh` to `/home/container/safe-start.sh`
   using the panel file manager, alongside `start-modules.sh`.
3. Change the server's startup command to `bash ./safe-start.sh`. Alternatively,
   update/import the egg and explicitly apply its new Default startup command to
   the server; existing server startup commands may not update automatically.
4. Enable `LOGCLEANER_STATUS=1` and restart the server. Confirm the console shows
   `[Logcleaner] Cleaning regular .log files only`.
5. Repeat the uptime test beyond eight hours and check PHP requests. This removes
   the cleaner's unsafe deletion behavior, but does not establish the cause of
   the reported delayed failure: the upstream cleaner also runs only at startup.

New servers use the embedded safe startup command without needing a separate
wrapper upload. Do not revert to `./start-modules.sh` with cleanup enabled, as
that bypasses this protection.

The embedded command carries a base64-encoded copy of `safe-start.sh` because
the image entrypoint flattens startup whitespace. Keep that payload synchronized
with the readable script when editing it; the regression tests verify this and
exercise the image's startup preprocessing.

Regression tests: `python3 -m unittest discover -s tests -v`.

### Cloudflare Tunnel Setup

1. Create a tunnel in your [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/).
2. Copy the token provided by Cloudflare.
3. Set `CLOUDFLARED_STATUS` to `1` (or `true`) in the server Startup settings.
4. Paste the token into the `CLOUDFLARED_TOKEN` variable.
5. Start the server.

### SSL with Certbot

To enable automatic SSL via Let's Encrypt:
1. Set `CERTBOT_STATUS` to `1`.
2. Configure `CERTBOT_EMAIL` and `CERTBOT_DOMAIN`.
3. Follow the instructions in the server console to add the required DNS TXT record.

## Credits

- **Fork & Adaptation for Pelican**: Vava22
- **Original Author**: [Ym0T](https://github.com/Ym0T)
- **Original Repository**: [pterodactyl-nginx-egg](https://github.com/Ym0T/pterodactyl-nginx-egg)

## License

[MIT License](https://choosealicense.com/licenses/mit/)
