#!/usr/bin/env bash
set -uo pipefail

SERVER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-./safe-start.sh}")" && pwd -P)" || exit 1
cd -- "$SERVER_DIR" || exit 1

clean_logs() {
    local log_dir="${LOG_DIR:-$SERVER_DIR/logs}"
    local max_size="${MAX_SIZE_MB:-10}"
    local max_age="${MAX_AGE_DAYS:-30}"
    local dry_run="${DRY_RUN:-false}"
    local file

    if [[ ! "$max_size" =~ ^[0-9]+$ || ! "$max_age" =~ ^[0-9]+$ ]]; then
        echo "[Logcleaner] Invalid size or age; skipping cleanup."
        return
    fi

    # Never clean temporary storage: it may contain live sockets and session data.
    if [[ ! -d "$log_dir" ]]; then
        echo "[Logcleaner] No log directory; skipping cleanup."
        return
    fi
    if [[ -L "$SERVER_DIR/logs" || -L "$log_dir" ]]; then
        echo "[Logcleaner] Refusing a symlinked log directory."
        return
    fi
    log_dir="$(realpath -e -- "$log_dir")" || return
    case "$log_dir" in
        "$SERVER_DIR/logs"|"$SERVER_DIR/logs/"*) ;;
        *)
            echo "[Logcleaner] Log directory must be inside $SERVER_DIR/logs; skipping cleanup."
            return
            ;;
    esac

    echo "[Logcleaner] Cleaning regular .log files only; runtime files are preserved."
    while IFS= read -r -d "" file; do
        # Recheck the type before truncating; do not follow log symlinks.
        [[ -f "$file" && ! -L "$file" ]] || continue
        if [[ "$dry_run" == "true" || "$dry_run" == "1" ]]; then
            printf "[Logcleaner][DRY-RUN] Would truncate: %s\n" "$file"
        else
            printf "[Logcleaner] Truncating: %s\n" "$file"
            # Preserve the inode so running services can keep writing and space is reclaimed.
            truncate --no-create --size=0 -- "$file" ||
                printf "[Logcleaner] Could not truncate: %s\n" "$file"
        fi
    done < <(find -P "$log_dir" -type f -name "*.log" \
        \( -size "+${max_size}M" -o -mtime "+${max_age}" \) -print0)
}

if [[ "${LOGCLEANER_STATUS:-false}" == "true" || "${LOGCLEANER_STATUS:-false}" == "1" ]]; then
    clean_logs
fi

# Keep the upstream cleaner disabled, including after an auto-update replaces modules.
export LOGCLEANER_STATUS=0
exec bash "$SERVER_DIR/start-modules.sh"
