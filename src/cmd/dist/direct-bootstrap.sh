#!/bin/sh
set -eu

root=${S_SOURCE_ROOT:-$(pwd)}
work=${1:-"$root/.bootstrap/direct"}
stage1=${S_DIRECT_BOOTSTRAP_STAGE1:-"$root/bin/s"}
source_file=${S_BOOTSTRAP_SOURCE:-"$root/src/cmd/compile/selfhost/compiler.s"}
verify="$root/misc/scripts/verify_true_selfhost.sh"

fail() {
    printf '%s\n' "direct bootstrap failed: $*" >&2
    exit 1
}

[ -x "$stage1" ] || fail "stage1 compiler not found: $stage1"
[ -f "$source_file" ] || fail "compiler source not found: $source_file"
[ -x "$verify" ] || fail "self-host verifier not found: $verify"

mkdir -p "$work"

# No compiler stage in this script may emit assembly or invoke as/ld. Each
# compiler must write the next ELF image directly from the S compiler source.
printf '%s\n' "[1/4] stage1 -> stage2 (direct ELF)"
"$stage1" build "$source_file" -o "$work/stage2" ||
    fail "stage1 cannot directly compile the complete S compiler yet"
"$verify" "$work/stage2"

printf '%s\n' "[2/4] stage2 -> stage3 (direct ELF)"
"$work/stage2" build "$source_file" -o "$work/stage3" ||
    fail "stage2 cannot directly compile the complete S compiler"
"$verify" "$work/stage3"

printf '%s\n' "[3/4] deterministic convergence"
cmp "$work/stage2" "$work/stage3" ||
    fail "stage2 and stage3 machine-code images differ"

printf '%s\n' "[4/4] generated compiler smoke test"
"$work/stage3" build "$root/test/selfhost/bootstrap_whole_program.s" \
    -o "$work/smoke"
set +e
"$work/smoke"
status=$?
set -e
[ "$status" -eq 42 ] || fail "generated program returned $status, want 42"

printf '%s\n' "DIRECT MACHINE-CODE SELF-HOST PASS"
