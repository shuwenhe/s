#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-nogc.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

cat >"$work/ownership_borrow_drop_gate.s" <<'SRC'
package mirnogc

func main() int {
    {
        owner := box(10)
        reader := &owner
        assert(*reader == 10)
        drop(reader)

        writer := &mut owner
        drop(writer)

        moved := owner
        assert(live_allocations() == 1)
    }

    assert(live_allocations() == 0)
    return 42
}
SRC

cat >"$work/reject_use_after_drop.s" <<'SRC'
package mirnogc_bad

func main() int {
    owner := box(1)
    reader := &owner
    drop(owner)
    return *reader
}
SRC

S_COMPILER_CFLAGS=-DS_COMPILER_CHECK_ALLOCATIONS "$root/bin/s" --emit-c "$work/ownership_borrow_drop_gate.s" "$work/ownership_borrow_drop_gate.c"
S_COMPILER_CFLAGS=-DS_COMPILER_CHECK_ALLOCATIONS "$root/bin/s" "$work/ownership_borrow_drop_gate.s" -o "$work/ownership_borrow_drop_gate"

set +e
"$work/ownership_borrow_drop_gate"
status=$?
set -e
if [ "$status" -ne 42 ]; then
    echo "mir-nogc gate: expected executable status 42, got $status" >&2
    exit 1
fi

if S_COMPILER_CFLAGS=-DS_COMPILER_CHECK_ALLOCATIONS "$root/bin/s" "$work/reject_use_after_drop.s" -o "$work/reject_use_after_drop" >/dev/null 2>"$work/reject.err"; then
    echo "mir-nogc gate: use-after-drop program unexpectedly compiled" >&2
    exit 1
fi

if ! grep -Eq 'drop|borrow|move|use after drop|dropped' "$work/reject.err"; then
    echo "mir-nogc gate: rejection did not mention ownership/borrow/drop semantics" >&2
    cat "$work/reject.err" >&2
    exit 1
fi

echo "MIR no-GC ownership/move/borrow/drop e2e gate passed"
