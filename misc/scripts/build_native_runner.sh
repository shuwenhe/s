#!/usr/bin/env bash
set -euo pipefail

#!/usr/bin/env bash
set -euo pipefail

# Determine repo root relative to this script if not provided
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SRC_ROOT="${SRC_ROOT:-$ROOT/src}"
OUT="${1:-/tmp/s_native}"
S_COMPILER_BIN="${S_COMPILER:-}"

# Transitional bootstrap chain:
# - prefer a local seed compiler when one is already available
# - fall back to the hosted compiler build path (python) otherwise

if [ -z "$S_COMPILER_BIN" ]; then
    for candidate in \
        "$ROOT/bin/s-native" \
        "$ROOT/bin/s" \
        "/home/shuwen/tmp/s_compiler_improved"
    do
        if [ -x "$candidate" ]; then
            S_COMPILER_BIN="$candidate"
            break
        fi
    done
fi

if [ -n "$S_COMPILER_BIN" ] && [ -x "$S_COMPILER_BIN" ]; then
    if "$S_COMPILER_BIN" build "$SRC_ROOT/runtime/runner.s" -o "$OUT"; then
        echo "built runner through seed compiler: $OUT"
        exit 0
    fi
    echo "seed compiler failed, falling back to python hosted compiler" >&2
fi

if command -v python3 >/dev/null 2>&1; then
    if (cd "$SRC_ROOT" && python3 -m compiler build "$SRC_ROOT/runtime/runner.s" -o "$OUT"); then
        echo "built runner through backend build path: $OUT"
        exit 0
    fi
fi

echo "python3 with hosted compiler support is required to build the runner" >&2
exit 1
