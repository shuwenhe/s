#!/usr/bin/env bash
set -euo pipefail

#!/usr/bin/env bash
set -euo pipefail

# Determine repository root relative to this script, allow override via ROOT env
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

SELFHOST_OUT="${1:-$ROOT/bin/s-selfhosted}"
NATIVE_OUT="$ROOT/bin/s-native"
SRC="$ROOT/src/runtime/s_selfhost_compiler_bootstrap.c"

# Build native runner using repo-relative script
"$ROOT/misc/scripts/build_native_runner.sh" "$NATIVE_OUT"

# Build self-host compiler launcher
cc -O2 -std=c11 "$SRC" -o "$SELFHOST_OUT"
echo "installed selfhost compiler launcher: $SELFHOST_OUT"
echo "installed native runner: $NATIVE_OUT"
