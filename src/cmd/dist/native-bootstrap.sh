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

# The seed participates only in construction of stage1.  Every later compiler
# must be emitted by the preceding S compiler directly from the same S source.
"$seed" "$source_file" "$work/stage1.ir"
S_SOURCE_ROOT="$root" "$seed" --emit-standalone-amd64 \
    "$work/stage1.ir" "$work/stage1"
"$verify" "$work/stage1"

compile_native_stage "$work/stage1" "$source_file" "$work/stage2"
"$verify" "$work/stage2"

compile_native_stage "$work/stage2" "$source_file" "$work/stage3"
"$verify" "$work/stage3"

cmp "$work/stage2" "$work/stage3" ||
    fail "stage2 and stage3 compiler binaries differ"

# Exercise the converged compiler instead of merely auditing its ELF headers.
"$work/stage2" --emit-asm \
    "$root/test/selfhost/bootstrap_native_multicall_args.s" \
    "$work/conformance.S"
as --64 -o "$work/conformance.o" "$work/conformance.S"
ld -static -T "$root/src/runtime/linker/nostdlib.ld" \
    -o "$work/conformance" "$runtime_object" "$work/conformance.o"
"$verify" "$work/conformance"
set +e
"$work/conformance"
status=$?
set -e
[ "$status" -eq 42 ] || fail "conformance program returned $status, want 42"

printf '%s\n' "native bootstrap passed: stage2 == stage3"
