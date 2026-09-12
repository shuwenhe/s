#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-borrow-df.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

cat >"$work/shared_shared.s" <<'SRC'
package borrowok

func main() int {
    x := box(42)
    p := &x
    q := &x
    return 0
}
SRC

cat >"$work/shared_mut.s" <<'SRC'
package borrowbad

func main() int {
    x := box(42)
    p := &x
    q := &mut x
    return 0
}
SRC

cat >"$work/mut_shared.s" <<'SRC'
package borrowbad

func main() int {
    x := box(42)
    p := &mut x
    q := &x
    return 0
}
SRC

cat >"$work/mut_mut.s" <<'SRC'
package borrowbad

func main() int {
    x := box(42)
    p := &mut x
    q := &mut x
    return 0
}
SRC

cat >"$work/maybe_borrow_move.s" <<'SRC'
package borrowdf

func main() int {
    x := box(42)
    if cond {
        p := &x
    } else {
    }
    y := x
    return 0
}
SRC

"$root/bin/s" --emit-mir "$work/shared_shared.s" "$work/shared_shared.mir"
if [ "$(grep -c 'Borrow(shared, _1)' "$work/shared_shared.mir" || true)" -ne 2 ]; then
    echo "mir borrow dataflow: shared + shared should be allowed" >&2
    cat "$work/shared_shared.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir "$work/shared_mut.s" "$work/shared_mut.mir"
if ! grep -q 'mir-error mutable borrow while shared borrowed' "$work/shared_mut.mir"; then
    echo "mir borrow dataflow: mutable borrow while shared borrowed should be rejected" >&2
    cat "$work/shared_mut.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir "$work/mut_shared.s" "$work/mut_shared.mir"
if ! grep -q 'mir-error shared borrow while mutably borrowed' "$work/mut_shared.mir"; then
    echo "mir borrow dataflow: shared borrow while mutably borrowed should be rejected" >&2
    cat "$work/mut_shared.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir "$work/mut_mut.s" "$work/mut_mut.mir"
if ! grep -q 'mir-error mutable borrow while mutably borrowed' "$work/mut_mut.mir"; then
    echo "mir borrow dataflow: second mutable borrow should be rejected" >&2
    cat "$work/mut_mut.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir "$work/maybe_borrow_move.s" "$work/maybe_borrow_move.mir"
if ! grep -q 'mir-error move of possibly borrowed value' "$work/maybe_borrow_move.mir"; then
    echo "mir borrow dataflow: move after branch borrow should be rejected" >&2
    cat "$work/maybe_borrow_move.mir" >&2
    exit 1
fi

echo "MIR borrow dataflow check passed"
