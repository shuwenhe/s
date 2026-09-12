#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-drop.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

cat >"$work/live_owner.s" <<'SRC'
package droplive
func main() int {
    x := box(42)
    return 0
}
SRC

cat >"$work/moved_owner.s" <<'SRC'
package dropmoved
func main() int {
    x := box(42)
    y := x
    return 0
}
SRC

cat >"$work/reference_owner.s" <<'SRC'
package dropref
func main() int {
    x := box(42)
    p := &x
    z := *p
    return z
}
SRC

cat >"$work/branch_moved.s" <<'SRC'
package dropbranch
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

cat >"$work/early_return.s" <<'SRC'
package dropearly
func main() int {
    x := box(42)
    if cond {
        return 1
    } else {
    }
    return 0
}
SRC

cat >"$work/lifo.s" <<'SRC'
package droplifo
func main() int {
    x := box(10)
    y := box(20)
    return 0
}
SRC

"$root/bin/s" --emit-mir "$work/moved_owner.s" "$work/moved_owner.raw"
if grep -q 'Drop(' "$work/moved_owner.raw"; then
    echo "mir drop elaboration: raw MIR must not contain implicit Drop" >&2
    cat "$work/moved_owner.raw" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-after-drop "$work/live_owner.s" "$work/live_owner.mir"
if ! grep -q 'Drop(_1)' "$work/live_owner.mir"; then
    echo "mir drop elaboration: live owner should be dropped" >&2
    cat "$work/live_owner.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-after-drop "$work/moved_owner.s" "$work/moved_owner.mir"
if grep -q 'Drop(_1)' "$work/moved_owner.mir"; then
    echo "mir drop elaboration: moved-from owner must not be dropped" >&2
    cat "$work/moved_owner.mir" >&2
    exit 1
fi
if ! grep -q 'Drop(_2)' "$work/moved_owner.mir"; then
    echo "mir drop elaboration: moved-to owner should be dropped" >&2
    cat "$work/moved_owner.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-after-drop "$work/reference_owner.s" "$work/reference_owner.mir"
if grep -q 'Drop(_2)' "$work/reference_owner.mir"; then
    echo "mir drop elaboration: references must not be owner-dropped" >&2
    cat "$work/reference_owner.mir" >&2
    exit 1
fi
if ! grep -q 'Drop(_1)' "$work/reference_owner.mir"; then
    echo "mir drop elaboration: borrowed owner should still be dropped" >&2
    cat "$work/reference_owner.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-after-drop "$work/branch_moved.s" "$work/branch_moved.mir"
if grep -q 'Drop(_1)' "$work/branch_moved.mir"; then
    echo "mir drop elaboration: branch moved owner must not be dropped at merge" >&2
    cat "$work/branch_moved.mir" >&2
    exit 1
fi
if [ "$(grep -c 'Drop(_' "$work/branch_moved.mir" || true)" -lt 2 ]; then
    echo "mir drop elaboration: branch-local moved owners should be dropped" >&2
    cat "$work/branch_moved.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-after-drop "$work/early_return.s" "$work/early_return.mir"
if [ "$(grep -c 'Drop(_1)' "$work/early_return.mir" || true)" -lt 2 ]; then
    echo "mir drop elaboration: every return path should drop live owner" >&2
    cat "$work/early_return.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-after-drop "$work/lifo.s" "$work/lifo.mir"
drop2_line=$(grep -n 'Drop(_2)' "$work/lifo.mir" | cut -d: -f1 | head -1)
drop1_line=$(grep -n 'Drop(_1)' "$work/lifo.mir" | cut -d: -f1 | head -1)
if [ -z "$drop2_line" ] || [ -z "$drop1_line" ] || [ "$drop2_line" -ge "$drop1_line" ]; then
    echo "mir drop elaboration: owners should drop in LIFO order" >&2
    cat "$work/lifo.mir" >&2
    exit 1
fi

echo "MIR drop elaboration check passed"
