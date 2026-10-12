#!/usr/bin/env bash
set -euo pipefail
[[ "${GIT_STATUS:-0}" =~ ^(true|1)$ ]] || exit 0
git_dir="${GIT_DIR:-/home/container/www}"
[[ -d "$git_dir/.git" ]] || { echo "[Git] No repository; skipping."; exit 0; }
cd -- "$git_dir"
export GIT_TERMINAL_PROMPT=0
stage="${HOME:-/home/container}/.pelican-git"
[[ ! -e "$stage" ]] || { echo "[Git] Stale credential workspace; skipping."; exit 0; }
mkdir -m 700 "$stage"
trap 'rm -rf -- "$stage"' EXIT
if [[ -n "${USERNAME:-}" && -n "${ACCESS_TOKEN:-}" ]]; then
    export GIT_ASKPASS="$stage/askpass"
    printf '%s\n' '#!/bin/bash' 'case "$1" in *Username*) printf "%s\n" "$USERNAME";; *) printf "%s\n" "$ACCESS_TOKEN";; esac' > "$GIT_ASKPASS"
    chmod 700 "$GIT_ASKPASS"
fi
branch=()
[[ -z "${GIT_BRANCH:-}" ]] || branch=(origin "$GIT_BRANCH")
if git pull --ff-only "${branch[@]}" > "$stage/result.log" 2>&1; then
    echo "[Git] Repository updated successfully."
else
    echo "[Git] Pull failed; check credentials, branch and local changes (site preserved)."
fi
