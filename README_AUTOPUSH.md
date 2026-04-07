Auto-push watcher for the `s` project
====================================

What this does
---------------
Creates a small local watcher that auto-stages, commits, and pushes changes to a configured Git remote/branch when files under the repo change.

Security / auth
---------------
- Recommended: configure SSH keys for GitHub or a credential helper (e.g., `git credential-manager` or `git config credential.helper store`).
- You may also set `GIT_AUTHOR_NAME` and `GIT_AUTHOR_EMAIL` to control commit author.

Quick start
-----------
1. Ensure you have a working git remote (SSH or HTTPS configured):

```bash
cd /home/shuwen/s
git remote -v
```

2. Run the watcher (example):

```bash
python3 s/tools/autopush.py --path /home/shuwen/s --debounce 2
```

Environment variables
---------------------
- `GIT_REMOTE` — remote name (default `origin`)
- `GIT_BRANCH` — branch to push (default: current branch)
- `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL` — optional commit author

Systemd service example
-----------------------
Create `/etc/systemd/system/s-autopush.service` with this content (edit paths as needed):

```ini
[Unit]
Description=S autopush watcher

[Service]
Type=simple
User=youruser
WorkingDirectory=/home/shuwen/s
ExecStart=/usr/bin/python3 /home/shuwen/s/tools/autopush.py --path /home/shuwen/s --debounce 2
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Notes
-----
- This tool is intentionally simple (polling). For robust production use, consider a more featureful watcher (inotify-based) or a CI workflow that commits from a central server.
- The script will only push if the local git configuration allows pushing without interactive credentials.
