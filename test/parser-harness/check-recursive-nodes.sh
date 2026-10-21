#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
compiler=${1:?usage: check-recursive-nodes.sh COMPILER}
work=$(mktemp -d /tmp/s-recursive-nodes.XXXXXXXX)
printf 'Recursive node artifacts=%s\n' "$work"
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
sha256sum "$compiler" test/parser-harness/fixtures/r_*.s \
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
for name in r_node_chain r_node_replace; do
    compile "$name"
    record "$work/$name.run.log" timeout 5s "$work/$name" || { cat "$work/$name.run.log" >&2; exit 1; }
    printf '%s: executed\n' "$name"
done
for name in r_null_read r_null_call; do
    compile "$name"
    status=0
    record "$work/$name.run.log" timeout 5s "$work/$name" || status=$?
    if [[ "$status" != 70 ]] || ! rg -q 'null struct reference' "$work/$name.run.log"; then
        cat "$work/$name.run.log" >&2; printf 'Expected checked null trap missing: %s\n' "$name" >&2; exit 1
    fi
    printf '%s: trapped before null access\n' "$name"
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
reject r_moved_node 'moved|unavailable'
reject r_wrong_node 'struct type mismatch'
reject r_self_cycle 'self field assignment'
reject r_shared_take 'cannot move.*borrowed'
reject r_null_scalar 'field assignment type mismatch'
printf 'Recursive owner links checked; real Parser execution remains a separate gate.\n'
