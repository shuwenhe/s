#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-move-df.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

cat >"$work/live_live.s" <<'SRC'
package livedf

func main() int {
    x := box(42)
    if cond {
    } else {
    }
    return *x
}
SRC

cat >"$work/moved_moved.s" <<'SRC'
package moveddf

func main() int {
    x := box(42)
    if cond {
        y := x
    } else {
        z := x
    }
    return 0
}
SRC

cat >"$work/live_moved.s" <<'SRC'
package maybedf

func main() int {
    x := box(42)
    if cond {
        y := x
    } else {
    }
    return *x
}
SRC

cat >"$work/use_after_move.s" <<'SRC'
package moveduse

func main() int {
    x := box(42)
    y := x
    return *x
}
SRC

cat >"$work/move_after_maybe.s" <<'SRC'
package maybemove

func main() int {
    x := box(42)
    if cond {
        y := x
    } else {
    }
    z := x
    return 0
}
SRC

"$root/bin/s" --emit-mir-after-drop "$work/live_live.s" "$work/live_live.mir"
if ! grep -q '_2 = Deref(_1)' "$work/live_live.mir"; then
    echo "mir move dataflow: LIVE + LIVE should allow Deref" >&2
    cat "$work/live_live.mir" >&2
    exit 1
fi
if ! grep -q 'Drop(_1)' "$work/live_live.mir"; then
    echo "mir move dataflow: LIVE + LIVE should drop owner" >&2
    cat "$work/live_live.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-after-drop "$work/moved_moved.s" "$work/moved_moved.mir"
if grep -q 'Drop(_1)' "$work/moved_moved.mir"; then
    echo "mir move dataflow: MOVED + MOVED must not drop moved-from owner" >&2
    cat "$work/moved_moved.mir" >&2
    exit 1
fi
if ! grep -q 'Return(0)' "$work/moved_moved.mir"; then
    echo "mir move dataflow: MOVED + MOVED should still allow unrelated return" >&2
    cat "$work/moved_moved.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir "$work/live_moved.s" "$work/live_moved.mir"
if ! grep -q 'mir-error use of possibly moved value' "$work/live_moved.mir"; then
    echo "mir move dataflow: LIVE + MOVED should become MAYBE_MOVED and reject use" >&2
    cat "$work/live_moved.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir "$work/use_after_move.s" "$work/use_after_move.mir"
if ! grep -q 'mir-error moved or unknown return value' "$work/use_after_move.mir"; then
    echo "mir move dataflow: use after MOVED should be rejected" >&2
    cat "$work/use_after_move.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir "$work/move_after_maybe.s" "$work/move_after_maybe.mir"
if ! grep -q 'mir-error move from possibly moved value' "$work/move_after_maybe.mir"; then
    echo "mir move dataflow: move after MAYBE_MOVED should be rejected" >&2
    cat "$work/move_after_maybe.mir" >&2
    exit 1
fi

echo "MIR move dataflow check passed"
