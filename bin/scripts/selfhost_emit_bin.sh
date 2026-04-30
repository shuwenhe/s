#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_COMPILER="$(ls -1t "$ROOT_DIR"/bin/c_arm64_* 2>/dev/null | head -n 1 || ls -1t "$ROOT_DIR"/bin/s_arm64_* 2>/dev/null | head -n 1 || true)"

COMPILER_PATH="${1:-$DEFAULT_COMPILER}"
OUT_BIN="${2:-$ROOT_DIR/bin/s_arm64_$(TZ=Asia/Shanghai date +%Y%m%d%H%M%S)}"
OUT_IR="${3:-/tmp/main_from_ir_bin_$(TZ=Asia/Shanghai date +%Y%m%d%H%M%S).ir}"
WORK_DIR="${4:-/tmp/ir_selfhost_for_emit_$(TZ=Asia/Shanghai date +%Y%m%d%H%M%S)}"

if [[ -z "$COMPILER_PATH" ]]; then
  echo "error: no compiler found. Pass compiler path as arg1, e.g. /app/s/bin/c_arm64_YYYYMMDDHHMMSS" >&2
  exit 1
fi

if [[ ! -x "$COMPILER_PATH" ]]; then
  echo "error: compiler is not executable: $COMPILER_PATH" >&2
  exit 1
fi

mkdir -p "$WORK_DIR"

echo "[1/3] bootstrap with: $COMPILER_PATH"
"$COMPILER_PATH" --bootstrap "$ROOT_DIR/src/cmd/compile/main.s" "$WORK_DIR"

echo "[2/3] emit native compiler binary from stage2 IR"
"$COMPILER_PATH" --emit-bin "$WORK_DIR/stage2.ir" "$OUT_BIN"
chmod +x "$OUT_BIN"

echo "[3/3] compile main.s with emitted compiler"
"$OUT_BIN" "$ROOT_DIR/src/cmd/compile/main.s" "$OUT_IR"

echo "done"
echo "compiler_bin=$OUT_BIN"
echo "compiled_ir=$OUT_IR"
echo "work_dir=$WORK_DIR"
sha256sum "$WORK_DIR/stage1.ir" "$WORK_DIR/stage2.ir" "$OUT_IR" | sed 's/^/sha256 /'
