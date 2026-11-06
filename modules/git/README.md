# Git Deploy Module

Keeps `www` in sync with your website's Git repository on every start, like
`git clone` the first time and `git fetch` + checkout afterwards. It runs before
Composer and cron so they see the updated code.

## Behaviour

- **No checkout yet:** clones `GIT_ADDRESS` into `www` if it is empty or holds only
  the installer's welcome page. A `www` with any other files is never cloned over;
  move them away (back up first) and restart.
- **Existing checkout:** points `origin` at `GIT_ADDRESS` (if set), fetches
  `GIT_BRANCH` (or the current branch, or the remote's default branch) and checks
  it out with `git checkout -B`, so `www` matches the remote branch. Changing
  `GIT_BRANCH` or `GIT_ADDRESS` takes effect on the next start.
- **Local edits:** untracked files (uploads, `.env`, `vendor/`) are left alone.
  Uncommitted edits to tracked files that the update would overwrite block the
  update instead of being lost. Commits made only in `www` are replaced by the
  remote branch.
- **Errors:** git's own error is shown, with credentials removed. Failures never
  stop the server; the current site keeps running.

## Configuration

| Env Variable | Default | Description |
|--------------|---------|-------------|
| `GIT_STATUS` | `0` | Enable the module |
| `GIT_ADDRESS` | empty | Website repository URL |
| `GIT_BRANCH` | empty | Branch to deploy; empty = current/default branch |
| `GIT_DIR` | `/home/container/www` | Folder to deploy into |
| `USERNAME`, `ACCESS_TOKEN` | empty | HTTPS credentials for private repositories (use a personal access token) |

Credentials are given to git through a temporary askpass helper and are never
written into the remote URL or console output.
