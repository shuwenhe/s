#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
compiler=${1:-$root/bin/s_compiler}
work=$(mktemp -d /tmp/s-owned-allocation.XXXXXXXX)
printf 'Owned allocation artifacts=%s\n' "$work"
cd "$root"
exec 3>"$work/commands.txt"
record() {
    local status=0
    local log=$1
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
if [[ "${S_HARNESS_SANITIZE:-0}" == 1 ]]; then
    cc_flags=(-fsanitize=address,undefined -fno-omit-frame-pointer)
fi
for name in typed_alloc owned_alloc_lifecycle owned_alloc_int owned_alloc_qualified owned_alloc_borrow owned_alloc_string_field; do
    record "$work/$name.compile.log" timeout 20s "$compiler" --emit-c \
        "test/parser-harness/fixtures/$name.s" "$work/$name.c" || {
        cat "$work/$name.compile.log" >&2
        exit 1
    }
    record "$work/$name.cc.log" "${CC:-cc}" -std=c11 -O1 -Wall -Wextra -Werror \
        "${cc_flags[@]}" -DS_COMPILER_CHECK_ALLOCATIONS -I src/runtime "$work/$name.c" -o "$work/$name" || {
        cat "$work/$name.cc.log" >&2
        exit 1
    }
    record "$work/$name.run.log" timeout 5s "$work/$name" || {
        cat "$work/$name.run.log" >&2
        exit 1
    }
    printf '%s: executed\n' "$name"
done
reject() {
    local name=$1 diagnostic=$2 status=0
    record "$work/$name.compile.log" timeout 20s "$compiler" --emit-c \
        "test/parser-harness/fixtures/$name.s" "$work/$name.c" || status=$?
    if [[ "$status" != 1 ]] || ! rg -q -- "$diagnostic" "$work/$name.compile.log"; then
        cat "$work/$name.compile.log" >&2
        printf 'Expected semantic rejection missing: %s\n' "$name" >&2
        exit 1
    fi
    printf '%s: rejected\n' "$name"
}
reject typed_alloc_unknown 'alloc requires a known type'
reject owned_alloc_value_operand 'alloc requires a known type'
reject owned_alloc_arity 'alloc expects exactly one type argument'
reject owned_alloc_use_after_move 'moved|unavailable'
reject owned_alloc_double_drop 'moved|unavailable|already'
reject owned_alloc_type_mismatch 'struct type mismatch'
reject owned_alloc_field_type 'field assignment type mismatch'
reject owned_alloc_unknown_field 'unknown owned struct field'
reject owned_alloc_foreign_type 'alloc requires a known type'
reject owned_alloc_drop_borrowed 'borrow'
reject owned_alloc_owner_field 'alloc currently requires scalar struct fields'
printf 'Owned allocation scalar/leaf-struct slice verified; alloc_array and Parser execution remain unproven.\n'
