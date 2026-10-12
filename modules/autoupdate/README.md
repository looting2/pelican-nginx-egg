# Release updates

Checks the latest published, stable GitHub release of `looting2/pelican-nginx-egg`
at startup. The original repository and Tavuru service are not contacted.

- `AUTOUPDATE_STATUS=1` enables checking.
- `AUTOUPDATE_FORCE=0` (default in the egg) only reports available versions.
- `AUTOUPDATE_FORCE=1` installs released scripts/modules, safe wrapper, helper and
  license and records the release tag in `VERSION`.

Configuration (`nginx/` and `php/`), websites, certificates, logs, runtime files and
images are never updated automatically. Back up customized runtime modules before
opting in. Config and image upgrades are manual. No releases, API rate limits and
download failures are nonfatal; stale `.runtime-update` directories must be
inspected and removed manually before trying again.

See the root README for release publishing and migration instructions.
