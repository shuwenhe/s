#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
compiler=${1:-$root/bin/s_compiler}
work=$(mktemp -d /tmp/s-owned-arrays.XXXXXXXX)
printf 'Owned array artifacts=%s\n' "$work"
cd "$root"
exec 3>"$work/commands.txt"
record() {
    local status=0 log=$1
    shift
    printf '%q ' "$@" >&3
    printf '\n' >&3
    "$@" > "$log" 2>&1 || status=$?
    printf '%s\n' "$status" > "$log.exit"
    return "$status"
}
git rev-parse HEAD > "$work/commit.txt"
git status --short > "$work/worktree.txt"
sha256sum "$compiler" test/parser-harness/fixtures/a_*.s \
    src/cmd/compile/internal/compiler/frontend.s src/runtime/compiler_runtime.h > "$work/input-hashes.txt"
printf 'sanitize=%s\nASAN_OPTIONS=%s\n' "${S_HARNESS_SANITIZE:-0}" "${ASAN_OPTIONS:-}" > "$work/sanitizers.txt"
cc_flags=()
if [[ "${S_HARNESS_SANITIZE:-0}" == 1 ]]; then cc_flags=(-fsanitize=address,undefined -fno-omit-frame-pointer); fi
compile() {
    local name=$1
    record "$work/$name.compile.log" timeout 20s "$compiler" --emit-c \
        "test/parser-harness/fixtures/$name.s" "$work/$name.c" || { cat "$work/$name.compile.log" >&2; return 1; }
    record "$work/$name.cc.log" "${CC:-cc}" -std=c11 -O1 -Wall -Wextra -Werror \
        "${cc_flags[@]}" -DS_COMPILER_CHECK_ALLOCATIONS -I src/runtime "$work/$name.c" -o "$work/$name" || {
        cat "$work/$name.cc.log" >&2; return 1;
    }
}
for name in a_int_array a_record_array a_array_copy a_qualified_array a_drop_hook; do
    compile "$name"
    record "$work/$name.run.log" timeout 5s "$work/$name" || { cat "$work/$name.run.log" >&2; exit 1; }
    printf '%s: executed\n' "$name"
done
record "$work/a_drop_hook.output.log" diff -u test/parser-harness/fixtures/a_drop_hook.stdout "$work/a_drop_hook.run.log"
trap_case() {
    local name=$1 diagnostic=$2 status=0
    compile "$name"
    record "$work/$name.run.log" timeout 5s "$work/$name" || status=$?
    if [[ "$status" != 70 ]] || ! rg -q -- "$diagnostic" "$work/$name.run.log"; then
        cat "$work/$name.run.log" >&2; printf 'Expected checked runtime trap missing: %s\n' "$name" >&2; exit 1
    fi
    printf '%s: trapped before invalid access\n' "$name"
}
trap_case a_negative_length 'negative array length'
trap_case a_bounds_read 'array index out of bounds'
trap_case a_bounds_write 'array index out of bounds'
trap_case a_zero_bounds 'array index out of bounds'
trap_case a_size_overflow 'array allocation size overflow'
trap_case a_copy_bounds 'array copy out of bounds'
reject() {
    local name=$1 diagnostic=$2 status=0
    record "$work/$name.compile.log" timeout 20s "$compiler" --emit-c \
        "test/parser-harness/fixtures/$name.s" "$work/$name.c" || status=$?
    if [[ "$status" != 1 ]] || ! rg -q -- "$diagnostic" "$work/$name.compile.log"; then
        cat "$work/$name.compile.log" >&2; printf 'Expected semantic rejection missing: %s\n' "$name" >&2; exit 1
    fi
    printf '%s: rejected\n' "$name"
}
reject a_use_after_move 'moved|unavailable'
reject a_element_type 'array element type mismatch'
reject a_record_type 'array element struct type mismatch'
reject a_copy_type 'array copy element type mismatch'
reject a_unknown_type 'alloc_array requires a known type'
reject a_bad_count 'array length requires an integer'
reject a_noncopyable_read 'array element copy requires copyable elements'
reject a_noncopyable_copy 'array copy requires copyable elements'
reject a_record_use_after_move 'moved|unavailable'
printf 'Owned integer/leaf-record arrays verified; Parser execution is a separate gate.\n'
