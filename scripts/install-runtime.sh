#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "${1:?Source directory required}" && pwd -P)"
target_dir="${2:?Target directory required}"
version="${3:?Version required}"
mode="${4:-install}"
mkdir -p "$target_dir"
cd -- "$target_dir"

# Validate the entire bundle before replacing any installed files.
for path in nginx php modules start-modules.sh safe-start.sh scripts/install-runtime.sh LICENSE; do
    [[ -e "$source_dir/$path" && ! -L "$source_dir/$path" ]] || {
        echo "[Runtime] Incomplete bundle: $path" >&2
        exit 1
    }
done
while IFS= read -r -d '' script; do
    bash -n "$script"
done < <(find "$source_dir/modules" "$source_dir/scripts" -type f -name '*.sh' -print0)
bash -n "$source_dir/start-modules.sh"
bash -n "$source_dir/safe-start.sh"

if [[ "$mode" == install ]]; then
    mkdir -p logs tmp www nginx php
    # Preserve existing site and server configuration on reinstall.
    cp -Rn "$source_dir/nginx/." nginx/
    cp -Rn "$source_dir/php/." php/
fi
apply_dir="$PWD/.runtime-apply"
mkdir "$apply_dir" || { echo "[Runtime] Stale .runtime-apply; inspect before retrying." >&2; exit 1; }
trap 'rm -rf -- "$apply_dir"' EXIT
mkdir "$apply_dir/modules" "$apply_dir/scripts"
cp -R "$source_dir/modules/." "$apply_dir/modules/"
cp "$source_dir/scripts/install-runtime.sh" "$apply_dir/scripts/"
cp "$source_dir/start-modules.sh" "$source_dir/safe-start.sh" "$source_dir/LICENSE" "$apply_dir/"
find "$apply_dir" -type f -name '*.sh' -exec chmod +x {} +
# Rename files instead of truncating scripts that may currently be running.
while IFS= read -r -d '' file; do
    relative="${file#"$apply_dir/"}"
    mkdir -p -- "$(dirname -- "$relative")"
    mv -f -- "$file" "$relative"
done < <(find "$apply_dir" -type f -print0)
printf '%s\n' "$version" > VERSION
echo "[Runtime] Installed $version; site, logs, tmp and configuration preserved."
