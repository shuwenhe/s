#!/usr/bin/env bash
set -euo pipefail

#!/usr/bin/env bash
set -euo pipefail

# Determine repo root relative to this script if not provided
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SRC_ROOT="${SRC_ROOT:-$ROOT/src}"
OUT="${1:-/tmp/s_native}"

# Transitional bootstrap chain:
# - prefer a stage1 S compiler if S_COMPILER is available
# - build the current runner entrypoint through the hosted compiler bridge

if [ -n "${S_COMPILER:-}" ] && [ -x "${S_COMPILER:-}" ]; then
    S_DISABLE_SELFHOSTED=1 "$S_COMPILER" build "$SRC_ROOT/runtime/runner.s" -o "$OUT"
    echo "built runner through S_COMPILER stage1: $OUT"
    exit 0
fi
echo "S_COMPILER stage1 compiler is required to build the runner" >&2
exit 1
