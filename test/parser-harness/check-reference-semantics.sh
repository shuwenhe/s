#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
compiler=${1:-$root/bin/s_compiler}
work=$(mktemp -d /tmp/s-reference-semantics.XXXXXXXX)
printf 'Reference semantics artifacts=%s\n' "$work"
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
sha256sum "$compiler" test/parser-harness/fixtures/*.s \
    src/cmd/compile/internal/compiler/frontend.s src/runtime/compiler_runtime.h > "$work/input-hashes.txt"
printf 'sanitize=%s\nASAN_OPTIONS=%s\n' "${S_HARNESS_SANITIZE:-0}" "${ASAN_OPTIONS:-}" > "$work/sanitizers.txt"
cc_flags=()
if [[ "${S_HARNESS_SANITIZE:-0}" == 1 ]]; then cc_flags=(-fsanitize=address,undefined -fno-omit-frame-pointer); fi
for name in h2_local_int source_reference h2_string_calls h2_string_statement_call h2_void_reference_call h2_string_shared_copy h2_string_reborrow h2_scalar_field h2_string_field h2_field_scope independent_field_borrows; do
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
        cat "$work/$name.compile.log" >&2
        printf 'Expected semantic rejection missing: %s\n' "$name" >&2; exit 1
    fi
    printf '%s: rejected\n' "$name"
}
reject reference_literal 'unknown variable|address requires'
reject h2_shared_string_write 'write requires an owner or mutable reference'
reject h2_assign_borrowed_local 'assign.*borrowed'
reject h2_conflicting_mutable 'conflicting borrow'
reject h2_copy_mutable 'mutable reference copying'
reject h2_reference_type_mismatch 'function argument type mismatch'
reject h2_dangling_local 'reference return must use a parameter'
reject h2_dangling_value_parameter 'reference return must use a borrowed parameter'
reject h2_dangling_owner_parameter 'reference return must use a borrowed parameter'
reject h2_read_mutably_borrowed 'read.*mutable borrow'
reject h2_drop_borrowed_struct 'borrow'
reject h2_aliasing_call 'conflicting borrow'
reject h2_read_borrowed_field 'read.*mutable borrow'
reject h2_upgrade_shared 'cannot mutably reborrow a shared reference'
reject h2_parent_write 'cannot write reference with a live reborrow'
reject h2_escape_in_struct 'reference fields require lifetime tracking'
reject h2_void_value 'void call cannot be used as a value'
printf 'Local scalar/string references verified; generic Parser pointer APIs remain unproven.\n'
