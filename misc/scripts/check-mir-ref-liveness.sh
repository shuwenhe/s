#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-ref-live.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

cat >"$work/borrow_then_move_bad.s" <<'SRC'
package reflive
func main() int {
    borrow_shared_field p _1 0
    move_field _1 0
    return 0
}
SRC

cat >"$work/borrow_use_then_move_ok.s" <<'SRC'
package reflive
func main() int {
    borrow_shared_field p _1 0
    use_ref p
    move_field _1 0
    return 0
}
SRC

cat >"$work/mut_borrow_use_then_shared_ok.s" <<'SRC'
package reflive
func main() int {
    borrow_mut_field p _1 0
    use_ref p
    borrow_shared_field q _1 0
    return 0
}
SRC

cat >"$work/nested_borrow_use_then_parent_mut_ok.s" <<'SRC'
package reflive
func main() int {
    borrow_shared_nested_field p _1 0 1
    use_ref p
    borrow_mut_field q _1 0
    return 0
}
SRC

cat >"$work/nested_borrow_parent_mut_bad.s" <<'SRC'
package reflive
func main() int {
    borrow_shared_nested_field p _1 0 1
    borrow_mut_field q _1 0
    return 0
}
SRC

cat >"$work/sibling_move_ok.s" <<'SRC'
package reflive
func main() int {
    borrow_shared_field p _1 0
    move_field _1 1
    return 0
}
SRC

"$root/bin/s" --emit-mir-reference-liveness "$work/borrow_then_move_bad.s" "$work/borrow_then_move_bad.mir"
if ! grep -Fq 'mir-error move of borrowed place Field(_1, 0)' "$work/borrow_then_move_bad.mir"; then
    echo "mir reference liveness: live reference should block move" >&2
    cat "$work/borrow_then_move_bad.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-reference-liveness "$work/borrow_use_then_move_ok.s" "$work/borrow_use_then_move_ok.mir"
for expected in \
    'p = Borrow(shared, Field(_1, 0))' \
    'UseRef(p)' \
    'EndBorrow(p, Field(_1, 0))' \
    'Move(Field(_1, 0)) OK'
do
    if ! grep -Fq "$expected" "$work/borrow_use_then_move_ok.mir"; then
        echo "mir reference liveness: borrow should end after last use: $expected" >&2
        cat "$work/borrow_use_then_move_ok.mir" >&2
        exit 1
    fi
done

"$root/bin/s" --emit-mir-reference-liveness "$work/mut_borrow_use_then_shared_ok.s" "$work/mut_borrow_use_then_shared_ok.mir"
for expected in \
    'p = Borrow(mut, Field(_1, 0))' \
    'EndBorrow(p, Field(_1, 0))' \
    'q = Borrow(shared, Field(_1, 0))'
do
    if ! grep -Fq "$expected" "$work/mut_borrow_use_then_shared_ok.mir"; then
        echo "mir reference liveness: mutable loan should end before later shared borrow: $expected" >&2
        cat "$work/mut_borrow_use_then_shared_ok.mir" >&2
        exit 1
    fi
done

"$root/bin/s" --emit-mir-reference-liveness "$work/nested_borrow_use_then_parent_mut_ok.s" "$work/nested_borrow_use_then_parent_mut_ok.mir"
if ! grep -Fq 'q = Borrow(mut, Field(_1, 0))' "$work/nested_borrow_use_then_parent_mut_ok.mir"; then
    echo "mir reference liveness: ended nested loan should not block parent mutable borrow" >&2
    cat "$work/nested_borrow_use_then_parent_mut_ok.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-reference-liveness "$work/nested_borrow_parent_mut_bad.s" "$work/nested_borrow_parent_mut_bad.mir"
if ! grep -Fq 'mir-error mutable borrow while shared borrowed Field(_1, 0)' "$work/nested_borrow_parent_mut_bad.mir"; then
    echo "mir reference liveness: live nested loan should block parent mutable borrow" >&2
    cat "$work/nested_borrow_parent_mut_bad.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-reference-liveness "$work/sibling_move_ok.s" "$work/sibling_move_ok.mir"
if ! grep -Fq 'Move(Field(_1, 1)) OK' "$work/sibling_move_ok.mir"; then
    echo "mir reference liveness: sibling field move should not overlap live borrow" >&2
    cat "$work/sibling_move_ok.mir" >&2
    exit 1
fi

echo "MIR reference liveness check passed"
