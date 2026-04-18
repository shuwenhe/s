#!/usr/bin/env bash
set -euo pipefail

# post-commit hook: append files-changed summary to commit message and push to origin
# - if remote/origin missing, prints a message and exits.
# - if commit message already contains 'files changed:' it will not amend.

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root_dir"

# ensure we are inside a git repo
if [ ! -d .git ]; then
  echo "[auto-push] not a git repository: $root_dir"
  exit 0
fi

# check remote
remote=$(git config --get remote.origin.url || true)
if [ -z "$remote" ]; then
  echo "[auto-push] no 'origin' remote configured; skipping auto-push"
  exit 0
fi

# quick connectivity/auth check (non-fatal)
if ! git ls-remote --exit-code --heads origin head >/dev/null 2>&1; then
  echo "[auto-push] cannot reach origin or authentication not configured; skipping auto-push"
  exit 0
fi

commit=$(git rev-parse --verify head)
msg=$(git log -1 --pretty=%b "$commit")

# if commit message already contains our marker, do nothing
if echo "$msg" | grep -q "^files changed:"; then
  echo "[auto-push] commit message already contains files changed; skipping amend"
else
  # list files changed in this commit
  files=$(git diff-tree --no-commit-id --name-only -r "$commit" | sed 's/^/- /')
  if [ -z "$files" ]; then
    echo "[auto-push] no files found in commit; skipping amend"
  else
    newmsg="$msg

files changed:
$files"
    # amend commit message (local only)
    git commit --amend -m "$newmsg"
    echo "[auto-push] amended commit message to include changed files"
    commit=$(git rev-parse --verify head)
  fi
fi

# push to origin (current branch)
branch=$(git rev-parse --abbrev-ref head)
if [ -z "$branch" ] || [ "$branch" = "head" ]; then
  echo "[auto-push] cannot determine current branch; skipping push"
  exit 0
fi

echo "[auto-push] pushing $commit to origin/$branch"
if git push origin "$branch"; then
  echo "[auto-push] push succeeded"
else
  echo "[auto-push] push failed; please run 'git push' manually and check authentication"
fi
