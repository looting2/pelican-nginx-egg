# Branch updates

Checks the newest commit of `looting2/pelican-nginx-egg`'s branch at startup
(the default branch, or `AUTOUPDATE_BRANCH` when set). Releases are not used, and
the original repository and Tavuru service are not contacted.

- `AUTOUPDATE_STATUS=1` enables checking.
- `AUTOUPDATE_FORCE=0` (default in the egg) only reports new commits.
- `AUTOUPDATE_FORCE=1` installs that commit's scripts/modules, safe wrapper, helper
  and license and records the commit hash in `VERSION`.
- `AUTOUPDATE_BRANCH` (optional) selects a branch other than the default branch.

Configuration (`nginx/` and `php/`), websites, certificates, logs, runtime files and
images are never updated automatically. Back up customized runtime modules before
opting in. Config and image upgrades are manual. Network failures, unknown branches
and download failures are nonfatal; stale `.runtime-update` directories must be
inspected and removed manually before trying again.
