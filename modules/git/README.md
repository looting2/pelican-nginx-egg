# Git Update Module

This module conditionally updates a Git repository at container startup.

## Features

- Conditional execution based on `GIT_STATUS` (1/0)
- Checks if the target directory is a Git repository; skips if not
- Fast-forward-only pull; preserves local changes on conflict
- Credentials supplied via an environment-backed askpass helper, never saved in remote URLs
- Robust execution with strict shell flags and error trapping

## Configuration

| Env Variable | Default                | Description                                    |
|--------------|------------------------|------------------------------------------------|
| `GIT_STATUS` | `0`                    | Whether to run the Git update script           |
| `GIT_DIR`    | `/home/container/www`  | Path to the Git repository directory           |
| `GIT_BRANCH` | empty | Optional branch to fast-forward (not a checkout switch) |
| `USERNAME`, `ACCESS_TOKEN` | empty | Optional HTTPS credentials for askpass |

## Example Egg JSON Variables

```json
"variables": [
  {
    "name": "Enable Git Update",
    "env_variable": "GIT_STATUS",
    "default_value": "0",
    "description": "Run Git update script on startup",
    "required": false
  },
  {
    "name": "Git Repository Directory",
    "env_variable": "GIT_DIR",
    "default_value": "/home/container/www",
    "description": "Path to the Git repository",
    "required": false
  }
]
```

## Script Details

- Uses `set -euo pipefail`; credential workspace is removed on exit.
- Raw Git errors are not printed to the panel console, avoiding credential disclosure.
- Honors `GIT_STATUS` to skip the entire Git workflow if disabled.

---
