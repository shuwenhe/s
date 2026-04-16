#!/usr/bin/env bash
set -euo pipefail

#!/usr/bin/env bash
set -euo pipefail

# Determine repo root relative to this script if not provided
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SRC_ROOT="${SRC_ROOT:-$ROOT/src}"
OUT="${1:-/tmp/s_native}"

# Bootstrap-native chain:
# - use the hosted compiler build path (python) if available
# - backend special-cases runtime/runner.s into a native executable

if command -v python3 >/dev/null 2>&1; then
    if (cd "$SRC_ROOT" && python3 -m compiler build "$SRC_ROOT/runtime/runner.s" -o "$OUT"); then
        echo "built native runner through backend build path: $OUT"
        exit 0
    fi
fi

echo "python3 with hosted compiler support is required to build the native runner" >&2
exit 1
