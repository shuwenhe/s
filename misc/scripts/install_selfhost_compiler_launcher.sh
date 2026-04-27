#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

TMPDIR="${TMPDIR:-/tmp}"
SELFHOST_OUT="$ROOT/bin/s-selfhosted"
FINAL_OUT="${1:-}"
NATIVE_OUT="$ROOT/bin/s-native"
SRC_S="$ROOT/src/runtime/s_selfhost_compiler_bootstrap.s"
WORKDIR="$(mktemp -d "${TMPDIR%/}/s-selfhost-XXXXXX")"

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

build_launcher() {
  local output="$1"

  if [ ! -f "$SRC_S" ]; then
    echo "missing S launcher source: $SRC_S" >&2
    return 1
  fi

  if [ ! -x "$NATIVE_OUT" ]; then
    echo "missing native runner: $NATIVE_OUT" >&2
    return 1
  fi

  "$NATIVE_OUT" build "$SRC_S" -o "$output"
}

install_launcher() {
  local source_path="$1"
  local output_path="$2"
  mkdir -p "$(dirname "$output_path")"
  cp "$source_path" "$output_path"
  chmod 0755 "$output_path"
}

"$ROOT/misc/scripts/build_native_runner.sh" "$NATIVE_OUT"

LAUNCHER_TMP="$WORKDIR/s_selfhost_compiler_launcher"
build_launcher "$LAUNCHER_TMP"
install_launcher "$LAUNCHER_TMP" "$SELFHOST_OUT"

if [ -n "$FINAL_OUT" ]; then
  install_launcher "$LAUNCHER_TMP" "$FINAL_OUT"
fi

echo "installed selfhost compiler launcher: $SELFHOST_OUT"
if [ -n "$FINAL_OUT" ]; then
  echo "installed final compiler launcher: $FINAL_OUT"
fi
echo "installed runner: $NATIVE_OUT"
