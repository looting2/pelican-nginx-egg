#!/usr/bin/env bash
set -euo pipefail
[[ "${GIT_STATUS:-0}" =~ ^(true|1)$ ]] || exit 0
git_dir="${GIT_DIR:-/home/container/www}"
# GIT_DIR names the site folder here, but git itself reads it as the .git location.
unset GIT_DIR GIT_WORK_TREE
repository="${GIT_ADDRESS:-}"
branch="${GIT_BRANCH:-}"
# The placeholder page the installer writes into an otherwise empty www.
welcome='<?php echo "Pelican Nginx is ready."; ?>'

export GIT_TERMINAL_PROMPT=0
stage="${HOME:-/home/container}/.pelican-git"
[[ ! -e "$stage" ]] || { echo "[Git] Stale credential workspace $stage; skipping. Remove it and restart."; exit 0; }
mkdir -m 700 "$stage"
trap 'rm -rf -- "$stage"' EXIT
if [[ -n "${USERNAME:-}" && -n "${ACCESS_TOKEN:-}" ]]; then
    # Credentials stay in the environment, not remote URLs or console output.
    export GIT_ASKPASS="$stage/askpass"
    printf '%s\n' '#!/bin/bash' 'case "$1" in *Username*) printf "%s\n" "$USERNAME";; *) printf "%s\n" "$ACCESS_TOKEN";; esac' > "$GIT_ASKPASS"
    chmod 700 "$GIT_ASKPASS"
fi

# Print git's own error without credentials embedded in URLs or the token itself.
show_log() {
    local line
    while IFS= read -r line; do
        line="$(sed -E 's#(https?://)[^/@[:space:]]*@#\1***@#g' <<< "$line")"
        [[ -z "${ACCESS_TOKEN:-}" ]] || line="${line//"$ACCESS_TOKEN"/***}"
        printf '[Git]   %s\n' "$line"
    done < <(tail -n 15 "$stage/git.log")
}

if [[ -n "$branch" ]] && ! git check-ref-format --branch "$branch" > /dev/null 2>&1; then
    echo "[Git] Invalid branch name; skipping (site preserved)."
    exit 0
fi

if [[ ! -d "$git_dir/.git" ]]; then
    [[ -n "$repository" ]] || { echo "[Git] No repository in $git_dir and no Git Repo Address set; skipping."; exit 0; }
    mkdir -p -- "$git_dir"
    # Only clone over an empty www or the installer's welcome page; never over a real site.
    mapfile -t existing < <(ls -A -- "$git_dir")
    if (( ${#existing[@]} > 1 )) || { (( ${#existing[@]} == 1 )) && \
        ! { [[ "${existing[0]}" == index.php ]] && [[ "$(cat -- "$git_dir/index.php")" == "$welcome" ]]; }; }; then
        echo "[Git] $git_dir already has files and is not a Git checkout; not cloning over them."
        echo "[Git] Move or delete its contents (back up first), then restart to clone $repository."
        exit 0
    fi
    branch_args=()
    [[ -z "$branch" ]] || branch_args=(--branch "$branch" --single-branch)
    echo "[Git] Cloning into $git_dir${branch:+ (branch $branch)}"
    if ! git clone "${branch_args[@]}" -- "$repository" "$stage/src" > "$stage/git.log" 2>&1; then
        show_log
        echo "[Git] Clone failed; check repository address, branch and credentials (site preserved)."
        exit 0
    fi
    rm -f -- "$git_dir/index.php"
    cp -a -- "$stage/src/." "$git_dir/"
    echo "[Git] Cloned $(git -C "$git_dir" rev-parse --short HEAD)."
    exit 0
fi

cd -- "$git_dir"
# Follow changes to the Git Repo Address variable.
if [[ -n "$repository" ]]; then
    git remote set-url origin "$repository" 2>/dev/null || git remote add origin "$repository"
fi
if [[ -z "$branch" ]]; then
    # No branch configured: stay on the current branch, or use the remote's default.
    branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
fi
if [[ -z "$branch" ]]; then
    branch="$(git ls-remote --symref origin HEAD 2> "$stage/git.log" | sed -n 's#^ref: refs/heads/\(.*\)\tHEAD$#\1#p')" || true
    [[ -n "$branch" ]] || { show_log; echo "[Git] Cannot determine the remote's default branch; set Git Branch (site preserved)."; exit 0; }
fi
if ! git fetch origin "$branch" > "$stage/git.log" 2>&1; then
    show_log
    echo "[Git] Fetch failed; check repository address, branch and credentials (site preserved)."
    exit 0
fi
before="$(git rev-parse --short HEAD 2>/dev/null || echo none)"
# Match the remote branch. Uncommitted edits to tracked files block the update instead of being lost.
if ! git checkout -B "$branch" FETCH_HEAD > "$stage/git.log" 2>&1; then
    show_log
    echo "[Git] Update blocked by local changes in $git_dir; commit, stash or revert them (site preserved)."
    exit 0
fi
git branch --set-upstream-to="origin/$branch" "$branch" > /dev/null 2>&1 || true
after="$(git rev-parse --short HEAD)"
if [[ "$before" == "$after" ]]; then
    echo "[Git] Already up to date at $after ($branch)."
else
    echo "[Git] Updated $before -> $after ($branch)."
fi
