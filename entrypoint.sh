#!/usr/bin/env bash
set -euo pipefail
cd "${HOME:-/home/container}"
export TZ="${TZ:-UTC}"
# Pelican placeholders become environment-variable references; preserve all whitespace.
startup="${STARTUP:-bash ./safe-start.sh}"
startup="${startup//\{\{/\$\{}"
startup="${startup//\}\}/\}}"
exec bash -c "$startup"
