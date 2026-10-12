# Safe startup log cleanup

Cleanup is owned by `safe-start.sh`. This module no longer deletes any files.
Run the egg's normal startup command: `bash ./safe-start.sh`.

Only regular `*.log` files inside the server's `logs/` directory are eligible.
Oversized or old logs are truncated in place. Symlinks, sockets, FIFO files, PHP
sessions and `tmp/` are preserved. Cleanup runs once at startup, not periodically.

Settings: `LOGCLEANER_STATUS=1`, `MAX_SIZE_MB=10`, `MAX_AGE_DAYS=30`;
`DRY_RUN=true` or `1` previews without modifying logs. `LOG_DIR` may select a
subdirectory under `logs/`, never an external or symlinked directory.

See the root README for migration instructions and regression tests.
