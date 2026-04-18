#!/usr/bin/env bash
set -euo pipefail

# installs the repository's sample post-commit hook into .git/hooks
root_dir="$(cd "$(dirname "$0")/.." && pwd)"
hook_src="$root_dir/scripts/post-commit-auto-push.sh"
hook_dst="$root_dir/.git/hooks/post-commit"

if [ ! -f "$hook_src" ]; then
  echo "hook source not found: $hook_src"
  exit 1
fi

if [ ! -d "$root_dir/.git" ]; then
  echo "no .git directory found in $root_dir; run this from the repository root"
  exit 1
fi

cp "$hook_src" "$hook_dst"
chmod +x "$hook_dst"
echo "installed post-commit hook to $hook_dst"
