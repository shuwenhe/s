#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
compiler=${1:?usage: check-typed-pointers.sh COMPILER}
work=$(mktemp -d /tmp/s-typed-pointers.XXXXXXXX)
printf 'Typed pointer artifacts=%s\n' "$work"
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
sha256sum "$compiler" test/parser-harness/fixtures/p_*.s \
    src/cmd/compile/internal/compiler/frontend.s > "$work/input-hashes.txt"
printf 'sanitize=%s\nASAN_OPTIONS=%s\n' "${S_HARNESS_SANITIZE:-0}" "${ASAN_OPTIONS:-}" > "$work/sanitizers.txt"
cc_flags=()
if [[ "${S_HARNESS_SANITIZE:-0}" == 1 ]]; then cc_flags=(-fsanitize=address,undefined -fno-omit-frame-pointer); fi
for name in p_struct_calls p_struct_views p_mutable_field_reference; do
    record "$work/$name.compile.log" timeout 20s "$compiler" --emit-c \
        "test/parser-harness/fixtures/$name.s" "$work/$name.c" || { cat "$work/$name.compile.log" >&2; exit 1; }
    record "$work/$name.cc.log" "${CC:-cc}" -std=c11 -O1 -Wall -Wextra -Werror \
        "${cc_flags[@]}" -DS_COMPILER_CHECK_ALLOCATIONS -I src/runtime "$work/$name.c" -o "$work/$name" || {
        cat "$work/$name.cc.log" >&2; exit 1;
    }
    record "$work/$name.run.log" timeout 5s "$work/$name" || { cat "$work/$name.run.log" >&2; exit 1; }
    printf '%s: executed\n' "$name"
done
reject() {
    local name=$1 diagnostic=$2 status=0
    record "$work/$name.compile.log" timeout 20s "$compiler" --emit-c \
        "test/parser-harness/fixtures/$name.s" "$work/$name.c" || status=$?
    if [[ "$status" != 1 ]] || ! rg -q -- "$diagnostic" "$work/$name.compile.log"; then
        cat "$work/$name.compile.log" >&2; printf 'Expected semantic rejection missing: %s\n' "$name" >&2; exit 1
    fi
    printf '%s: rejected\n' "$name"
}
reject p_shared_write 'shared struct reference'
reject p_shared_upgrade 'mutable struct reference'
reject p_wrong_type 'struct type mismatch'
reject p_alias_call 'conflicting.*borrow'
reject p_drop_borrowed 'ownership move/borrow|borrowed'
reject p_move_field 'cannot move.*borrowed'
reject p_copy_mutable 'mutable reference copying'
reject p_owner_read 'cannot read field during a mutable borrow'
reject p_borrowed_escape 'return type mismatch'
reject p_shared_method 'shared struct reference'
reject p_partial_owner 'partially moved struct'
printf 'Typed struct calls checked; recursive nodes and Parser execution are separate gates.\n'
