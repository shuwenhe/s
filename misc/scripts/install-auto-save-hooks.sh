#!/bin/sh

set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOKS_DIR="$ROOT_DIR/.githooks"

if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "install-auto-save-hooks: not a git repository: $ROOT_DIR" >&2
    exit 1
fi

if [ ! -d "$HOOKS_DIR" ]; then
    echo "install-auto-save-hooks: missing hooks directory: $HOOKS_DIR" >&2
    exit 1
fi

git -C "$ROOT_DIR" config core.hooksPath .githooks
chmod +x "$HOOKS_DIR"/post-commit "$HOOKS_DIR"/post-merge

echo "Installed git hooks for $ROOT_DIR"
echo "core.hooksPath=.githooks"
