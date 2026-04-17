#!/usr/bin/env bash
set -euo pipefail

# Installs the repository's sample post-commit hook into .git/hooks
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK_SRC="$ROOT_DIR/scripts/post-commit-auto-push.sh"
HOOK_DST="$ROOT_DIR/.git/hooks/post-commit"

if [ ! -f "$HOOK_SRC" ]; then
  echo "hook source not found: $HOOK_SRC"
  exit 1
fi

if [ ! -d "$ROOT_DIR/.git" ]; then
  echo "No .git directory found in $ROOT_DIR; run this from the repository root"
  exit 1
fi

cp "$HOOK_SRC" "$HOOK_DST"
chmod +x "$HOOK_DST"
echo "Installed post-commit hook to $HOOK_DST"
