#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

TMPDIR="${TMPDIR:-/tmp}"
SELFHOST_OUT="$ROOT/bin/s-selfhosted"
FINAL_OUT="${1:-}"
NATIVE_OUT="$ROOT/bin/s-native"
SOURCE_ENTRY="$ROOT/src/cmd/compile/main.s"
BOOTSTRAP_COMPILER="${S_COMPILER:-$NATIVE_OUT}"
WORKDIR="$(mktemp -d "${TMPDIR%/}/s-selfhost-XXXXXX")"

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

build_compiler() {
  local output="$1"

  if [ ! -f "$SOURCE_ENTRY" ]; then
    echo "missing compiler entry source: $SOURCE_ENTRY" >&2
    return 1
  fi

  if [ ! -x "$BOOTSTRAP_COMPILER" ]; then
    echo "missing bootstrap compiler: $BOOTSTRAP_COMPILER" >&2
    return 1
  fi

  "$BOOTSTRAP_COMPILER" build "$SOURCE_ENTRY" -o "$output"
}

install_launcher() {
  local source_path="$1"
  local output_path="$2"
  mkdir -p "$(dirname "$output_path")"
  cp "$source_path" "$output_path"
  chmod 0755 "$output_path"
}

if [ ! -x "$NATIVE_OUT" ]; then
  "$ROOT/misc/scripts/build_native_runner.sh" "$NATIVE_OUT"
fi

COMPILER_TMP="$WORKDIR/s_selfhost_compiler"
build_compiler "$COMPILER_TMP"
install_launcher "$COMPILER_TMP" "$SELFHOST_OUT"

if [ -n "$FINAL_OUT" ]; then
  install_launcher "$COMPILER_TMP" "$FINAL_OUT"
fi

echo "installed selfhost compiler: $SELFHOST_OUT"
if [ -n "$FINAL_OUT" ]; then
  echo "installed final compiler: $FINAL_OUT"
fi
echo "bootstrap compiler used: $BOOTSTRAP_COMPILER"
