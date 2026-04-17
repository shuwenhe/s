#!/usr/bin/env bash
set -euo pipefail

# post-commit hook: append files-changed summary to commit message and push to origin
# - If remote/origin missing, prints a message and exits.
# - If commit message already contains 'Files changed:' it will not amend.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# Ensure we are inside a git repo
if [ ! -d .git ]; then
  echo "[auto-push] not a git repository: $ROOT_DIR"
  exit 0
fi

# Check remote
REMOTE=$(git config --get remote.origin.url || true)
if [ -z "$REMOTE" ]; then
  echo "[auto-push] no 'origin' remote configured; skipping auto-push"
  exit 0
fi

# Quick connectivity/auth check (non-fatal)
if ! git ls-remote --exit-code --heads origin HEAD >/dev/null 2>&1; then
  echo "[auto-push] cannot reach origin or authentication not configured; skipping auto-push"
  exit 0
fi

COMMIT=$(git rev-parse --verify HEAD)
MSG=$(git log -1 --pretty=%B "$COMMIT")

# If commit message already contains our marker, do nothing
if echo "$MSG" | grep -q "^Files changed:"; then
  echo "[auto-push] commit message already contains Files changed; skipping amend"
else
  # List files changed in this commit
  FILES=$(git diff-tree --no-commit-id --name-only -r "$COMMIT" | sed 's/^/- /')
  if [ -z "$FILES" ]; then
    echo "[auto-push] no files found in commit; skipping amend"
  else
    NEWMSG="$MSG

Files changed:
$FILES"
    # Amend commit message (local only)
    git commit --amend -m "$NEWMSG"
    echo "[auto-push] amended commit message to include changed files"
    COMMIT=$(git rev-parse --verify HEAD)
  fi
fi

# Push to origin (current branch)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ -z "$BRANCH" ] || [ "$BRANCH" = "HEAD" ]; then
  echo "[auto-push] cannot determine current branch; skipping push"
  exit 0
fi

echo "[auto-push] pushing $COMMIT to origin/$BRANCH"
if git push origin "$BRANCH"; then
  echo "[auto-push] push succeeded"
else
  echo "[auto-push] push failed; please run 'git push' manually and check authentication"
fi
