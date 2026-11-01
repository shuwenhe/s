#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
compiler=${1:-$root/bin/s_compiler}
work=$(mktemp -d /tmp/s-existing-references.XXXXXXXX)
printf 'Existing reference regression artifacts=%s\n' "$work"
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
    src/cmd/compile/internal/compiler/frontend.s > "$work/input-hashes.txt"
failed=0
for name in box_reference box_mutation box_field_mutation independent_field_borrows functions pair array; do
    source="test/parser-harness/fixtures/$name.s"
    expected=0
    if [[ "$name" == functions || "$name" == pair || "$name" == array ]]; then
        source="test/compiler/$name.s"
        expected=42
        sha256sum "$source" >> "$work/input-hashes.txt"
    fi
    record "$work/$name.compile.log" timeout 20s "$compiler" --emit-c "$source" \
        "$work/$name.c" || {
        cat "$work/$name.compile.log" >&2
        failed=1
        continue
    }
    record "$work/$name.cc.log" "${CC:-cc}" -std=c11 -O1 -Wall -Wextra -Werror -DS_COMPILER_CHECK_ALLOCATIONS \
        -I src/runtime "$work/$name.c" -o "$work/$name" || {
        cat "$work/$name.cc.log" >&2
        failed=1
        continue
    }
    status=0
    record "$work/$name.run.log" timeout 5s "$work/$name" || status=$?
    if [[ "$status" != "$expected" ]]; then cat "$work/$name.run.log" >&2; failed=1; continue; fi
    printf '%s: executed, exit=%s\n' "$name" "$status"
done
status=0
record "$work/shared_reference_write.log" timeout 20s "$compiler" --emit-c \
    test/parser-harness/fixtures/shared_reference_write.s "$work/shared_reference_write.c" || status=$?
if [[ "$status" != 1 ]] || ! rg -q 'write requires an owner or mutable reference' "$work/shared_reference_write.log"; then
    cat "$work/shared_reference_write.log" >&2
    printf 'Shared-reference write did not produce the expected semantic rejection.\n' >&2
    failed=1
fi
record "$work/assertion_failure.compile.log" timeout 20s "$compiler" --emit-c \
    test/parser-harness/fixtures/assertion_failure.s "$work/assertion_failure.c"
record "$work/assertion_failure.cc.log" "${CC:-cc}" -std=c11 -O1 -Wall -Wextra -Werror \
    -I src/runtime "$work/assertion_failure.c" -o "$work/assertion_failure"
status=0
record "$work/assertion_failure.run.log" timeout 5s "$work/assertion_failure" || status=$?
if [[ "$status" != 17 ]]; then printf 'Failed assertion exit was %s, expected 17\n' "$status" >&2; exit 1; fi
printf 'Deliberately failed assertion: exit=17\n'
printf 'Raw Parser pointer interfaces remain unproven; regression failure flag=%s\n' "$failed"
exit "$failed"
