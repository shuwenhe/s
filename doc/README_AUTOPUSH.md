auto-push watcher for the `s` project
====================================

what this does
---------------
creates a small local watcher that auto-stages, commits, and pushes changes to a configured git remote/branch when files under the repo change.

security / auth
---------------
- recommended: configure ssh keys for github or a credential helper (e.g., `git credential-manager` or `git config credential.helper store`).
- you may also set `git_author_name` and `git_author_email` to control commit author.

quick start
-----------
1. ensure you have a working git remote (ssh or https configured):

```bash
cd /home/shuwen/s
git remote -v
```

2. run the watcher (example):

```bash
python3 s/tools/autopush.py --path /home/shuwen/s --debounce 2
```

environment variables
---------------------
- `git_remote` — remote name (default `origin`)
- `git_branch` — branch to push (default: current branch)
- `git_author_name`, `git_author_email` — optional commit author

systemd service example
-----------------------
create `/etc/systemd/system/s-autopush.service` with this content (edit paths as needed):

```ini
[unit]
description=s autopush watcher

[service]
type=simple
user=youruser
workingdirectory=/home/shuwen/s
execstart=/usr/bin/python3 /home/shuwen/s/tools/autopush.py --path /home/shuwen/s --debounce 2
restart=on-failure

[install]
wantedby=multi-user.target
```

notes
-----
- this tool is intentionally simple (polling). for robust production use, consider a more featureful watcher (inotify-based) or a ci workflow that commits from a central server.
- the script will only push if the local git configuration allows pushing without interactive credentials.
