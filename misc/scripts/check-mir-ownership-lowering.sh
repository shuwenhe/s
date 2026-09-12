#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-lowering.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

cat >"$work/box_move_deref_drop.s" <<'SRC'
package mirlower

func main() int {
    x := box(42)
    y := x
    return *y
}
SRC

cat >"$work/use_after_move.s" <<'SRC'
package mirbad

func main() int {
    x := box(42)
    y := x
    return *x
}
SRC

cat >"$work/borrow_deref.s" <<'SRC'
package mirborrow

func main() int {
    x := box(42)
    y := x
    p := &y
    z := *p
    return z
}
SRC

cat >"$work/move_while_borrowed.s" <<'SRC'
package mirborrowbad

func main() int {
    x := box(42)
    p := &x
    y := x
    return *y
}
SRC

cat >"$work/mut_borrow_deref.s" <<'SRC'
package mirmut

func main() int {
    x := box(42)
    p := &mut x
    z := *p
    return z
}
SRC

"$root/bin/s" --emit-mir "$work/box_move_deref_drop.s" "$work/box_move_deref_drop.mir"

box_count=$(grep -c 'Box(' "$work/box_move_deref_drop.mir" || true)
move_count=$(grep -c 'Move(' "$work/box_move_deref_drop.mir" || true)
deref_count=$(grep -c 'Deref(' "$work/box_move_deref_drop.mir" || true)
drop_count=$(grep -c 'Drop(' "$work/box_move_deref_drop.mir" || true)

if [ "$box_count" -lt 1 ]; then
    echo "mir ownership lowering: expected Box >= 1" >&2
    cat "$work/box_move_deref_drop.mir" >&2
    exit 1
fi
if [ "$move_count" -lt 1 ]; then
    echo "mir ownership lowering: expected Move >= 1" >&2
    cat "$work/box_move_deref_drop.mir" >&2
    exit 1
fi
if [ "$deref_count" -lt 1 ]; then
    echo "mir ownership lowering: expected Deref >= 1" >&2
    cat "$work/box_move_deref_drop.mir" >&2
    exit 1
fi
if [ "$drop_count" -ne 1 ]; then
    echo "mir ownership lowering: expected exactly one Drop" >&2
    cat "$work/box_move_deref_drop.mir" >&2
    exit 1
fi
if grep -q 'Drop(_1)' "$work/box_move_deref_drop.mir"; then
    echo "mir ownership lowering: moved-from _1 must not be dropped" >&2
    cat "$work/box_move_deref_drop.mir" >&2
    exit 1
fi
if ! grep -q 'Drop(_2)' "$work/box_move_deref_drop.mir"; then
    echo "mir ownership lowering: moved-to _2 must be dropped" >&2
    cat "$work/box_move_deref_drop.mir" >&2
    exit 1
fi
if ! grep -q 'Return(_3)' "$work/box_move_deref_drop.mir"; then
    echo "mir ownership lowering: return must consume Deref result" >&2
    cat "$work/box_move_deref_drop.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir "$work/use_after_move.s" "$work/use_after_move.mir"
if ! grep -q 'mir-error moved or unknown return value' "$work/use_after_move.mir"; then
    echo "mir ownership lowering: use-after-move must be rejected by MIR builder" >&2
    cat "$work/use_after_move.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir "$work/borrow_deref.s" "$work/borrow_deref.mir"
if ! grep -q 'Borrow(shared, _2)' "$work/borrow_deref.mir"; then
    echo "mir ownership lowering: expected shared Borrow from moved owner" >&2
    cat "$work/borrow_deref.mir" >&2
    exit 1
fi
if ! grep -q '_4 = Deref(_3)' "$work/borrow_deref.mir"; then
    echo "mir ownership lowering: expected Deref from borrow value" >&2
    cat "$work/borrow_deref.mir" >&2
    exit 1
fi
if grep -q 'Drop(_3)' "$work/borrow_deref.mir"; then
    echo "mir ownership lowering: borrow value must not receive owner Drop" >&2
    cat "$work/borrow_deref.mir" >&2
    exit 1
fi
if ! grep -q 'Drop(_2)' "$work/borrow_deref.mir"; then
    echo "mir ownership lowering: borrowed owner must still be dropped" >&2
    cat "$work/borrow_deref.mir" >&2
    exit 1
fi
if ! grep -q 'Return(_4)' "$work/borrow_deref.mir"; then
    echo "mir ownership lowering: return must use named deref value" >&2
    cat "$work/borrow_deref.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir "$work/move_while_borrowed.s" "$work/move_while_borrowed.mir"
if ! grep -q 'mir-error move of borrowed value' "$work/move_while_borrowed.mir"; then
    echo "mir ownership lowering: move while borrowed must be rejected" >&2
    cat "$work/move_while_borrowed.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir "$work/mut_borrow_deref.s" "$work/mut_borrow_deref.mir"
if ! grep -q 'Borrow(mut, _1)' "$work/mut_borrow_deref.mir"; then
    echo "mir ownership lowering: expected mutable Borrow" >&2
    cat "$work/mut_borrow_deref.mir" >&2
    exit 1
fi

echo "MIR ownership lowering check passed"
