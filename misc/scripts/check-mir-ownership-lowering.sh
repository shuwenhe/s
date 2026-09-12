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

echo "MIR ownership lowering check passed"
