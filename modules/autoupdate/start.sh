#!/usr/bin/env bash
set -euo pipefail

[[ "${AUTOUPDATE_STATUS:-1}" =~ ^(true|1)$ ]] || exit 0
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$root"
stage="$root/.runtime-update"
[[ ! -e "$stage" ]] || { echo "[AutoUpdate] Stale .runtime-update; skipping. Inspect and remove it manually."; exit 0; }
mkdir "$stage"
trap 'rm -rf -- "$stage"' EXIT

# Track the newest commit of this fork's branch (default branch unless AUTOUPDATE_BRANCH is set).
repository="https://github.com/looting2/pelican-nginx-egg"
branch="${AUTOUPDATE_BRANCH:-}"
if [[ -n "$branch" ]]; then
    [[ "$branch" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ && "$branch" != *..* ]] || { echo "[AutoUpdate] Invalid branch name; skipping."; exit 0; }
    ref="refs/heads/$branch"
else
    ref="HEAD"
fi
if ! version="$(GIT_TERMINAL_PROMPT=0 timeout 60 git ls-remote "$repository.git" "$ref" 2>/dev/null | cut -f1 | head -n1)"; then
    version=""
fi
[[ "$version" =~ ^[0-9a-f]{40}$ ]] || { echo "[AutoUpdate] Cannot resolve branch ${branch:-default} commit; keeping installed runtime."; exit 0; }
installed="$(cat VERSION 2>/dev/null || true)"
[[ "$installed" != "$version" ]] || { echo "[AutoUpdate] Already on ${branch:-default branch} commit ${version:0:12}."; exit 0; }
echo "[AutoUpdate] New ${branch:-default branch} commit ${version:0:12} available (installed: ${installed:-unknown})."
[[ "${AUTOUPDATE_FORCE:-0}" =~ ^(true|1)$ ]] || { echo "[AutoUpdate] Check-only mode; no files changed."; exit 0; }
if ! curl --fail --silent --show-error --location --connect-timeout 10 --max-time 180 \
    "https://codeload.github.com/looting2/pelican-nginx-egg/tar.gz/$version" -o "$stage/runtime.tar.gz"; then
    echo "[AutoUpdate] Download failed; keeping installed runtime."
    exit 0
fi
mkdir "$stage/source"
if ! tar -xzf "$stage/runtime.tar.gz" -C "$stage/source" --strip-components=1 --wildcards \
    '*/nginx/*' '*/php/*' '*/modules/*' '*/start-modules.sh' '*/safe-start.sh' '*/scripts/*.sh' '*/LICENSE'; then
    echo "[AutoUpdate] Invalid bundle; keeping installed runtime."
    exit 0
fi
if bash "$stage/source/scripts/install-runtime.sh" "$stage/source" "$root" "$version" update; then
    echo "[AutoUpdate] Updated runtime; configuration and image upgrades remain manual."
else
    echo "[AutoUpdate] Runtime update failed; inspect server files before next restart." >&2
fi
