#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-nogc-check.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

cat >"$work/ownership.s" <<'SRC'
package ownership
func main() int {
    owner := box(20);
    {
        reference := &mut owner;
        *reference = *reference + 1;
    }
    moved := owner;
    {
        first := &moved;
        second := &moved;
        assert(*first == *second);
    }
    moved = box(*moved * 2);
    return *moved;
}
SRC

cat >"$work/hello.s" <<'SRC'
package main
func main() {
    println("Hello, world!")
    return
}
SRC

cat >"$work/reject.s" <<'SRC'
package bad
func main() int {
    a := box(1);
    r := &a;
    drop(a);
    return *r;
}
SRC

"$root/bin/s" "$work/ownership.s" -o "$work/ownership"
set +e
"$work/ownership"
status=$?
set -e
test "$status" -eq 42

"$root/bin/s" "$work/hello.s" -o "$work/hello"
test "$("$work/hello")" = "Hello, world!"

if nm "$work/hello" "$work/ownership" | grep -E 'runtime_gc|run_gc|mark_roots|sweep_pass|runtime_execute|SSEED|gc_' >/dev/null; then
    echo "GC or seed runtime symbol linked into no-GC binary" >&2
    exit 1
fi

if "$root/bin/s" "$work/reject.s" -o "$work/reject" >/dev/null 2>&1; then
    echo "borrow violation unexpectedly compiled" >&2
    exit 1
fi

echo "No-GC compiler checks passed"
