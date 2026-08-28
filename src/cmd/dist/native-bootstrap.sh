#!/usr/bin/env sh
set -eu

if [ "${S_SOURCE_ROOT:-}" = "" ]; then
    S_SOURCE_ROOT=$(pwd)
fi

SELFHOST_DIR=${1:-}
if [ -z "$SELFHOST_DIR" ]; then
    printf '%s\n' "usage: S_SOURCE_ROOT=/path/to/s ./src/cmd/dist/native-bootstrap.sh <output-dir>" >&2
    exit 1
fi

seed_compiler="$S_SOURCE_ROOT/bin/s_seed"
compiler_src="$S_SOURCE_ROOT/src/cmd/compile/selfhost/compiler.s"

if [ ! -x "$seed_compiler" ]; then
    printf '%s\n' "missing seed compiler: $seed_compiler" >&2
    exit 1
fi

mkdir -p "$SELFHOST_DIR"

stage1_ir="$SELFHOST_DIR/stage1.ir"
stage1_bin="$SELFHOST_DIR/stage1"
stage2_ir="$SELFHOST_DIR/stage2.ir"
stage2_bin="$SELFHOST_DIR/stage2"
stage3_ir="$SELFHOST_DIR/stage3.ir"
stage3_bin="$SELFHOST_DIR/stage3"

printf '%s\n' "[1/5] seed -> stage1"
"$seed_compiler" "$compiler_src" "$stage1_ir"
"$seed_compiler" --emit-standalone-amd64 "$stage1_ir" "$stage1_bin"

printf '%s\n' "[2/5] stage1 -> stage2"
"$stage1_bin" "$compiler_src" "$stage2_ir"
"$stage1_bin" --emit-bin "$stage2_ir" "$stage2_bin"

printf '%s\n' "[3/5] stage2 -> stage3"
"$stage2_bin" "$compiler_src" "$stage3_ir"
"$stage2_bin" --emit-bin "$stage3_ir" "$stage3_bin"

printf '%s\n' "[4/5] verify convergence"
cmp "$stage2_ir" "$stage3_ir"
cmp "$stage2_bin" "$stage3_bin"

printf '%s\n' "[5/5] verify native compiler"
"$S_SOURCE_ROOT/misc/scripts/verify_true_selfhost.sh" "$stage2_bin"

printf '%s\n' "native bootstrap converged: $stage2_bin"
