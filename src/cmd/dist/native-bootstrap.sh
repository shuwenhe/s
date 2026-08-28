#!/bin/sh
set -eu

root=${S_SOURCE_ROOT:-$(pwd)}
work=${1:-"$root/.bootstrap/native"}
seed=${S_BOOTSTRAP_SEED:-"$root/bin/s_seed"}
source_file=${S_BOOTSTRAP_SOURCE:-"$root/src/cmd/compile/selfhost/compiler.s"}
verify="$root/misc/scripts/verify_true_selfhost.sh"

fail() {
    printf '%s\n' "native bootstrap failed: $*" >&2
    exit 1
}

[ -x "$seed" ] || fail "trusted seed compiler not found: $seed"
[ -f "$source_file" ] || fail "compiler source not found: $source_file"
[ -x "$verify" ] || fail "self-host verifier not found: $verify"

mkdir -p "$work"

runtime_object="$work/selfhost_runtime.o"
as --64 -o "$runtime_object" "$root/src/runtime/selfhost_linux_amd64.S"
stage_manifest="$work/manifest.txt"
write_manifest="$root/src/cmd/dist/checks/write-manifest.sh"

compile_native_stage() {
    compiler=$1
    input=$2
    output=$3
    assembly="${output}.S"
    object="${output}.o"
    "$compiler" --emit-asm "$input" "$assembly"
    as --64 -o "$object" "$assembly"
    ld -static -T "$root/src/runtime/linker/nostdlib.ld" \
        -o "$output" "$runtime_object" "$object"
}

# The seed participates only in construction of stage1. Every later compiler
# is emitted by the preceding S compiler directly from the same S source.
printf '%s\n' "[1/7] seed -> stage1"
"$seed" "$source_file" "$work/stage1.ir"
S_SOURCE_ROOT="$root" "$seed" --emit-standalone-amd64 \
    "$work/stage1.ir" "$work/stage1"
"$verify" "$work/stage1"
printf '%s\n' "seed -> stage1             PASS"

printf '%s\n' "[2/7] stage1 -> stage2"
"$work/stage1" "$source_file" "$work/stage2.ir"
compile_native_stage "$work/stage1" "$source_file" "$work/stage2"
"$verify" "$work/stage2"
printf '%s\n' "stage1 -> stage2           PASS"

printf '%s\n' "[3/7] stage2 -> stage3"
"$work/stage2" "$source_file" "$work/stage3.ir"
compile_native_stage "$work/stage2" "$source_file" "$work/stage3"
"$verify" "$work/stage3"
printf '%s\n' "stage2 -> stage3           PASS"

printf '%s\n' "[4/7] convergence"
cmp "$work/stage2.ir" "$work/stage3.ir" || fail "stage2.ir and stage3.ir differ"
printf '%s\n' "IR convergence             PASS"
cmp "$work/stage2" "$work/stage3" || fail "stage2 and stage3 compiler binaries differ"
printf '%s\n' "binary convergence         PASS"

printf '%s\n' "[5/7] seed dependency audit"
"$verify" "$work/stage2"
printf '%s\n' "seed dependency audit      PASS"

printf '%s\n' "[6/7] stage2 compiler smoke test"
"$work/stage2" --emit-asm \
    "$root/test/selfhost/bootstrap_native_multicall_args.s" \
    "$work/conformance.S"
printf '%s\n' "stage2 compiler smoke test PASS"

printf '%s\n' "[7/7] conformance"
as --64 -o "$work/conformance.o" "$work/conformance.S"
ld -static -T "$root/src/runtime/linker/nostdlib.ld" \
    -o "$work/conformance" "$runtime_object" "$work/conformance.o"
"$verify" "$work/conformance"
set +e
"$work/conformance"
status=$?
set -e
[ "$status" -eq 42 ] || fail "conformance program returned $status, want 42"
printf '%s\n' "conformance                PASS"

printf '%s\n' ""
"$write_manifest" "$work" "$stage_manifest" "$runtime_object"

printf '%s\n' "S NATIVE BOOTSTRAP"
printf '%s\n' "================================================================"
printf '%s\n' "seed -> stage1             PASS"
printf '%s\n' "stage1 -> stage2           PASS"
printf '%s\n' "stage2 -> stage3           PASS"
printf '%s\n' "IR convergence             PASS"
printf '%s\n' "binary convergence         PASS"
printf '%s\n' "seed dependency audit      PASS"
printf '%s\n' "conformance                PASS"
printf '%s\n' "manifest                   $stage_manifest"
printf '%s\n' ""
printf '%s\n' "RESULT: NATIVE BOOTSTRAP COMPLETE"
