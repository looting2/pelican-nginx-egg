#!/usr/bin/env bash
set -euo pipefail

[[ "${AUTOUPDATE_STATUS:-1}" =~ ^(true|1)$ ]] || exit 0
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$root"
stage="$root/.runtime-update"
[[ ! -e "$stage" ]] || { echo "[AutoUpdate] Stale .runtime-update; skipping. Inspect and remove it manually."; exit 0; }
mkdir "$stage"
trap 'rm -rf -- "$stage"' EXIT

# Only published releases of this fork are eligible, never upstream or moving main.
if ! curl --fail --silent --show-error --location --connect-timeout 10 --max-time 60 \
    https://api.github.com/repos/looting2/pelican-nginx-egg/releases/latest -o "$stage/release.json"; then
    echo "[AutoUpdate] Release lookup unavailable (or no releases); keeping installed runtime."
    exit 0
fi
if ! version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("tag_name", ""))' "$stage/release.json" 2>/dev/null)"; then
    echo "[AutoUpdate] Invalid release response; keeping installed runtime."
    exit 0
fi
[[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "[AutoUpdate] Invalid release tag; skipping."; exit 0; }
installed="$(cat VERSION 2>/dev/null || true)"
[[ "$installed" != "$version" ]] || { echo "[AutoUpdate] Already on $version."; exit 0; }
echo "[AutoUpdate] Release $version available (installed: ${installed:-unknown})."
[[ "${AUTOUPDATE_FORCE:-0}" =~ ^(true|1)$ ]] || { echo "[AutoUpdate] Check-only mode; no files changed."; exit 0; }
if ! curl --fail --silent --show-error --location --connect-timeout 10 --max-time 180 \
    "https://codeload.github.com/looting2/pelican-nginx-egg/tar.gz/refs/tags/$version" -o "$stage/runtime.tar.gz"; then
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
