#!/usr/bin/env bash
set -euo pipefail

echo "[SETUP] Installing installer dependencies"
apt-get update -qq
apt-get install -y --no-install-recommends ca-certificates curl git tar
cd "${SERVER_DIR:-/mnt/server}"
mkdir -p logs tmp www
stage="$PWD/.runtime-install"
[[ ! -e "$stage" ]] || { echo "[SETUP] Remove stale .runtime-install after checking its contents."; exit 1; }
mkdir "$stage"
trap 'rm -rf -- "$stage"' EXIT
repository="https://github.com/looting2/pelican-nginx-egg"
revision="$(git ls-remote "$repository.git" HEAD | cut -f1)"
[[ "$revision" =~ ^[0-9a-f]{40}$ ]] || { echo "[SETUP] Cannot resolve runtime revision."; exit 1; }
curl --fail --silent --show-error --location \
    "https://codeload.github.com/looting2/pelican-nginx-egg/tar.gz/$revision" -o "$stage/runtime.tar.gz"
mkdir "$stage/source"
tar -xzf "$stage/runtime.tar.gz" -C "$stage/source" --strip-components=1 --wildcards \
    '*/nginx/*' '*/php/*' '*/modules/*' '*/start-modules.sh' '*/safe-start.sh' '*/scripts/*.sh' '*/LICENSE'
bash "$stage/source/scripts/install-runtime.sh" "$stage/source" "$PWD" "$revision"

# Never remove an existing site during reinstall.
if [[ -n "${GIT_ADDRESS:-}" ]]; then
    if [[ -n "$(ls -A www)" ]]; then
        echo "[Git] Existing www preserved; use GIT_STATUS for subsequent pulls."
    else
        export GIT_TERMINAL_PROMPT=0
        if [[ -n "${USERNAME:-}" && -n "${ACCESS_TOKEN:-}" ]]; then
            # Credentials stay in the environment, not remote URLs or console output.
            export GIT_ASKPASS="$stage/askpass"
            printf '%s\n' '#!/bin/bash' 'case "$1" in *Username*) printf "%s\n" "$USERNAME";; *) printf "%s\n" "$ACCESS_TOKEN";; esac' > "$GIT_ASKPASS"
            chmod 700 "$GIT_ASKPASS"
        fi
        branch=()
        [[ -z "${GIT_BRANCH:-}" ]] || branch=(--branch "$GIT_BRANCH" --single-branch)
        if ! git clone "${branch[@]}" -- "$GIT_ADDRESS" www > "$stage/git.log" 2>&1; then
            echo "[Git] Clone failed; check repository URL, branch and credentials." >&2
            exit 1
        fi
    fi
elif [[ "${WORDPRESS:-0}" =~ ^(true|1)$ && -z "$(ls -A www)" ]]; then
    curl --fail --silent --show-error --location https://wordpress.org/latest.tar.gz -o "$stage/wordpress.tar.gz"
    tar -xzf "$stage/wordpress.tar.gz" -C www --strip-components=1
elif [[ -z "$(ls -A www)" ]]; then
    printf '%s\n' '<?php echo "Pelican Nginx is ready."; ?>' > www/index.php
fi
echo "[DONE] Runtime installed. Start the server with bash ./safe-start.sh."
