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

cat >"$work/string_helper.s" <<'SRC'
package strings
func say(string message) {
    println(message)
}
func main() {
    message := "Hello from helper"
    say(message)
    return
}
SRC

cat >"$work/struct_pair.s" <<'SRC'
package structs
struct Pair {
    left box
    right box
}
func sum(Pair p) int {
    return *p.left + *p.right
}
func main() int {
    {
        p := Pair(box(20), box(22))
        assert(sum(p) == 42)
    }
    assert(live_allocations() == 0)
    return 42
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

"$root/bin/s" "$work/string_helper.s" -o "$work/string_helper"
test "$("$work/string_helper")" = "Hello from helper"

S_COMPILER_CFLAGS=-DS_COMPILER_CHECK_ALLOCATIONS "$root/bin/s" "$work/struct_pair.s" -o "$work/struct_pair"
set +e
"$work/struct_pair"
status=$?
set -e
test "$status" -eq 42

if nm "$work/hello" "$work/ownership" "$work/string_helper" "$work/struct_pair" | grep -E 'runtime_gc|run_gc|mark_roots|sweep_pass|runtime_execute|SSEED|gc_' >/dev/null; then
    echo "GC or seed runtime symbol linked into no-GC binary" >&2
    exit 1
fi

if "$root/bin/s" "$work/reject.s" -o "$work/reject" >/dev/null 2>&1; then
    echo "borrow violation unexpectedly compiled" >&2
    exit 1
fi

echo "No-GC compiler checks passed"
