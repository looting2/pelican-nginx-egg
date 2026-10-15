# Nginx Cloudflare Egg

A versatile **Pelican Panel Egg** featuring Nginx, PHP 8.x, WordPress, Git, Composer, Cronjob, ionCube Loader, Auto-Update, and Cloudflare Tunnel support.

**Maintained independently by looting2**, with the Pelican adaptation by Vava22.
The MIT runtime was originally adapted from [Ym0T's Pterodactyl Nginx Egg](https://github.com/Ym0T/pterodactyl-nginx-egg),
vendored from commit `2342c44c7234b9a06f01bc869fbcd505157b50d9`.
Installation, release updates and image publishing now use **this repository**,
not the original repository, images or version service.

## Features

- 🔄 **Auto-Update**: Checks this fork's published GitHub releases; applying runtime updates is opt-in
- 🧹 **LogCleaner**: Truncates oversized or old logs without touching temporary/runtime files (dry-run supported)
- 🌱 **Git Module**: Auto `git pull` on restart
- 📦 **Composer Module**: Installs packages from `composer.json` or a fallback variable
- 🔐 **ionCube Loader**: Auto-detected and enabled for encrypted PHP
- 🌐 **Cloudflare Tunnel**: Environment-token configuration and connection checks
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

### Publish the images first (maintainer)

The egg references `ghcr.io/looting2/pelican-nginx-egg:8.2-latest` through
`:8.5-latest`. These tags are **not guaranteed to exist yet**. Before selecting them:

1. Merge these files into this repository's default `main` branch.
2. Run **Publish PHP images** in GitHub Actions (also runs weekly and on image changes).
   The workflow uses `GITHUB_TOKEN` with `packages: write`; enable Actions and allow
   publishing packages in the repository/organization settings.
3. Verify all four builds finish and make the GHCR package **public** so Wings can
   pull without registry credentials. Each tag includes `linux/amd64` and `linux/arm64`.
4. If hosting a differently named fork, change the owner/repository in the egg,
   installer, updater, Dockerfile label and workflow tags before publishing.

Local build: `docker build --build-arg PHP_VERSION=8.4 -t pelican-nginx:8.4 .`.
The Debian-based image installs Nginx, PHP from Sury, Composer, Certbot, Cloudflared, OpenSSH Client
and an optional ionCube loader. Optional PHP extensions are installed when Sury
provides packages; unavailable ones are reported during build. ionCube may not yet
support every PHP version/architecture. ImageMagick's default security policy is
not weakened. Builds still require these third-party package/download services;
independence from the original egg does not mean offline installation.

### Import the egg

1. Download the egg file (`egg-pelican-nginx.json`).
2. In your **Pelican Panel**, navigate to **Nests** in the sidebar.
3. Click **Import Egg**.
4. Create a new server and select the **Pelican Nginx** egg.
5. Choose the Docker image matching your desired PHP version.
6. Fill in all required variables, including whether **WordPress** is desired and the PHP version field (must be set explicitly).

The installer resolves this repository's default-branch commit, downloads its
archive, extracts only the runtime bundle, and installs `nginx/`, `php/`, all `modules/`, `start-modules.sh`,
`safe-start.sh`, the runtime install helper and `LICENSE`. It records the commit in
`VERSION`. `www`, existing Nginx/PHP configuration, logs and runtime files are
preserved on reinstall. Git deployment and WordPress are initialized only into an
empty `www`; Git takes precedence if both are selected. Otherwise a simple welcome
page is created at `www/index.php` (not a public `phpinfo()` page).

## Configuration

| Variable | Default | Description |
| :--- | :--- | :--- |
| `AUTOUPDATE_STATUS` | `1` | Enable (`1`) or disable (`0`) auto-update checks |
| `AUTOUPDATE_FORCE` | `0` | Opt in to applying released runtime scripts (`1`) or just check (`0`) |
| `PHP_VERSION` | - | **Required**. Must match the Docker image tag (e.g., `8.4`) |
| `WORDPRESS` | `0` | Set to `1` to install WordPress automatically |
| `LOGCLEANER_STATUS` | `1` | Enable (`1`/`true`) safe startup log cleanup; disable with `0`/`false` |
| `CLOUDFLARED_STATUS` | `0` | Enable Cloudflare Tunnel (`1`) |
| `CLOUDFLARED_TOKEN` | - | Your Cloudflare Tunnel token (starts with `ey...`) |

### OpenSSH Client and PHP-FPM subprocesses

The runtime image includes OpenSSH Client (`/usr/bin/ssh`), not an SSH server.
For an existing deployment, publish updated images using **Publish PHP images**
after merging the Dockerfile change into `main`. Select the image matching
`PHP_VERSION` in Pelican, have Wings pull the updated tag, and recreate/restart
the server container. This requires administrator/provider access; installing
packages on the Wings host or in the egg's installer container does not install
them in the running server. Runtime auto-updates do not update container images.

`proc_open` is already allowed by the bundled PHP configuration. PHP-FPM loads
`/home/container/php/php.ini` by default (or the `PHP_INI` override), rather than
necessarily using the same configuration as CLI PHP. For existing servers:

1. Back up the active PHP configuration. If `proc_open` appears in its
   `disable_functions` list, remove only that entry; keep other restrictions.
2. Check `/home/container/php/pool.d/*.conf` (or pools included by your custom
   `PHP_FPM_CONF`) for `php_admin_value[disable_functions]` or
   `php_value[disable_functions]` overrides that also disable `proc_open`.
3. Restart the server to reload PHP-FPM. Reinstalling or updating the runtime
   preserves existing PHP configuration, so it will not remove custom restrictions.

Verify `/usr/bin/ssh -V` inside the running server container. Through a temporary,
access-restricted PHP web endpoint, check `function_exists('proc_open')` and
`ini_get('disable_functions')`; remove the endpoint immediately afterward.
Checking CLI PHP alone does not verify PHP-FPM's settings.

Use `/usr/bin/ssh` explicitly when launching it from PHP to avoid PHP-FPM PATH
differences. Keep private keys outside `www`, restrict their permissions, and
verify remote host keys using a trusted `known_hosts` file; do not disable host
key checking. Only permit subprocess execution for trusted application code,
and never pass untrusted input to a shell command.

### PHP mail() via SMTP

The runtime image includes `msmtp-mta`, which provides `/usr/sbin/sendmail` for
PHP's built-in `mail()` function. No separate PHPMailer library or mail daemon is
required. You still need an SMTP provider; installing the transport alone does
not configure email delivery.

Create `/home/container/.msmtprc` (outside the public web directory) with your
provider's settings, for example:

```ini
defaults
auth on
tls on
tls_starttls on
tls_trust_file /etc/ssl/certs/ca-certificates.crt

account default
host smtp.example.com
port 587
from sender@example.com
user sender@example.com
passwordeval "cat /home/container/.smtp-password"
```

Store only your SMTP password in `/home/container/.smtp-password`. Both files
must be owned by the container user and have permissions `0600`. Never place
credentials in `/home/container/www`, commit them, or disable TLS certificate
verification. For providers using implicit TLS on port 465, set `port 465` and
`tls_starttls off`. Use a sender address authorized by your provider.

For existing servers, publish and pull the updated image matching `PHP_VERSION`,
then recreate/restart the container as described above. Installing packages on
the host or in the installer container does not fix the runtime image. In the
active `/home/container/php/php.ini` (or `PHP_INI` override), set:

```ini
sendmail_path = "/usr/sbin/sendmail --file=/home/container/.msmtprc -t -i"
```

Check custom PHP-FPM pools for `sendmail_path` overrides and restart PHP-FPM
after changing its configuration. Existing PHP configuration is preserved during
reinstall and runtime updates, so it must be updated manually.

If the application reports sendmail as missing even though
`/usr/sbin/sendmail --version` works in the running container, check PHP-FPM's
active `open_basedir`. PHP filesystem checks cannot see paths outside that list.
The bundled configuration allows the executable and its resolved msmtp symlink
target without granting access to all of `/usr`:

```ini
open_basedir = /home/container:/tmp:/usr/sbin/sendmail:/usr/bin/msmtp
```

For existing configurations, retain your current allowed paths and append
`/usr/sbin/sendmail:/usr/bin/msmtp`. Check pool-level `open_basedir` overrides too,
then restart the server. Do not disable `open_basedir` to fix detection.
A fresh installation gets this setting, but reinstalling over an existing server
preserves its PHP configuration. If the version command itself fails, the
runtime image still needs to be updated; reinstalling server files is not enough.

Verify `/usr/sbin/sendmail --version` inside the running container, then send a
test message from your application's mail test screen using PHP `mail()` (or
its “Sendmail” option). Check the container console for SMTP errors and confirm
receipt; an accepted message does not guarantee inbox delivery. Alternatively,
select your application's “SMTP server” option and configure the provider there
directly; that bypasses `sendmail` and does not need this transport.

### Safe Log Cleanup

The egg startup command runs `bash ./safe-start.sh`, a safe cleaner before launching the vendored
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

The wrapper disables a second LogCleaner run for the rest of startup, including
after release updates. The legacy destructive cleaner has been removed.

#### Testing on an existing server (no reinstall required)

1. Back up your current startup command and logs you want to retain.
2. Upload this repository's `safe-start.sh` to `/home/container/safe-start.sh`
   using the panel file manager, alongside `start-modules.sh`.
3. Change the server's startup command to `bash ./safe-start.sh`. Alternatively,
   update/import the egg and explicitly apply its new Default startup command to
   the server; existing server startup commands may not update automatically.
4. Disable auto-updates on a still-upstream runtime (`AUTOUPDATE_STATUS=0`).
   Enable `LOGCLEANER_STATUS=1` and restart the server. Confirm the console shows
   `[Logcleaner] Cleaning regular .log files only`.
5. Repeat the uptime test beyond eight hours and check PHP requests. This removes
   the cleaner's unsafe deletion behavior, but does not establish the cause of
   the reported delayed failure: the upstream cleaner also runs only at startup.

New servers get the wrapper from the installer. Do not use `./start-modules.sh`
as normal startup, as it bypasses cleanup. The owned image entrypoint preserves
startup whitespace and converts Pelican `{{VARIABLE}}` placeholders to shell
environment-variable references without flattening the command.

Regression tests: `python3 -m unittest discover -s tests -v`.

### Release updates

Create a **published, non-prerelease GitHub release in this repository** to offer
runtime updates. With `AUTOUPDATE_STATUS=1`, startup queries GitHub's latest release.
No releases, rate limits, or download failure leave the runtime alone. With
`AUTOUPDATE_FORCE=0` (default) it only reports availability. With `1`, it replaces
modules, orchestration, safe wrapper, helper and license, then records the release
tag in `VERSION`. It does **not** change `www`, Nginx/PHP configuration, certificates,
logs, `tmp`, or container images. Back up customized modules/scripts before opting in.
New installs track the default-branch commit; the first release check can therefore
report a release even if that commit already contains its changes. Forced updates
select the latest published release, not necessarily the newest default-branch code.
Image upgrades require selecting/re-pulling a published image and restarting.
Config changes in releases must be reviewed and applied manually.

### Migrate an existing server off the original runtime

1. **Back up the entire server**, startup settings, image choice and environment
   variables. Stop the server and disable upstream auto-updates.
2. Publish and verify this fork's public images as described above.
3. Prefer manual upload over running an old destructive reinstall script: upload
   this repository's `modules/`, `scripts/install-runtime.sh`, `start-modules.sh`,
   `safe-start.sh` and `LICENSE`, replacing the old runtime scripts. Keep your
   existing `nginx/`, `php/`, `www/`, certificates, logs and `tmp/`.
   Record the downloaded revision in `VERSION` or leave it absent for check-only
   release detection. The orchestrator invokes uploaded scripts through Bash, so
   file-manager uploads do not require preserving executable bits.
4. Import/update the egg, explicitly apply `bash ./safe-start.sh` to this server,
   select this fork's matching PHP image, and set `AUTOUPDATE_FORCE=0`.
   Existing servers may retain their old startup command/image after an egg import.
5. Restart and test PHP, site routes, Cloudflare and enabled modules. Keep your
   backup for rollback. Only consider reinstalling after applying the **new**
   installer and taking the backup; never use the previous upstream installer.

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

Certbot uses interactive manual DNS-01 validation; it does not auto-renew.
Review `nginx/conf.d/default-ssl.conf.example` to configure HTTPS yourself.
`CERTBOT_WEBROOT_PATH` is retained for compatibility but is unused in DNS-01 mode.

## Credits

- **Fork & Adaptation for Pelican**: Vava22
- **Independent maintenance & images**: looting2
- **Original Author**: [Ym0T](https://github.com/Ym0T)
- **Original Repository**: [pterodactyl-nginx-egg](https://github.com/Ym0T/pterodactyl-nginx-egg)

## License

[MIT License](LICENSE), including the original author's copyright and permission notice.
