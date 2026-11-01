#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-loan-live.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

cat >"$work/multiple_use.s" <<'SRC'
package loanlive
func main() int {
    borrow_shared_field p _1 0
    use_ref p
    move_field _1 0
    use_ref p
    move_field _1 0
    return 0
}
SRC

cat >"$work/branch_join_use.s" <<'SRC'
package loanlive
func main() int {
    borrow_shared_field p _1 0
    if cond {
        use_ref p
    } else {
    }
    move_field _1 0
    use_ref p
    move_field _1 0
    return 0
}
SRC

cat >"$work/two_refs_same_place.s" <<'SRC'
package loanlive
func main() int {
    borrow_shared_field p _1 0
    borrow_shared_field q _1 0
    use_ref p
    move_field _1 0
    use_ref q
    move_field _1 0
    return 0
}
SRC

cat >"$work/sibling_place.s" <<'SRC'
package loanlive
func main() int {
    borrow_shared_field p _1 0
    move_field _1 1
    use_ref p
    move_field _1 0
    return 0
}
SRC

"$root/bin/s" --emit-mir-loan-liveness "$work/multiple_use.s" "$work/multiple_use.mir"
if [ "$(grep -Fc 'UseRef(p)' "$work/multiple_use.mir" || true)" -ne 2 ]; then
    echo "mir loan liveness: multiple uses should both remain visible" >&2
    cat "$work/multiple_use.mir" >&2
    exit 1
fi
if [ "$(grep -Fc 'EndBorrow(p, Field(_1, 0))' "$work/multiple_use.mir" || true)" -ne 1 ]; then
    echo "mir loan liveness: loan should end exactly once at last use" >&2
    cat "$work/multiple_use.mir" >&2
    exit 1
fi
first_move_line=$(grep -Fn 'mir-error move of borrowed place Field(_1, 0)' "$work/multiple_use.mir" | cut -d: -f1 | head -1)
end_line=$(grep -Fn 'EndBorrow(p, Field(_1, 0))' "$work/multiple_use.mir" | cut -d: -f1 | head -1)
ok_move_line=$(grep -Fn 'Move(Field(_1, 0)) OK' "$work/multiple_use.mir" | cut -d: -f1 | tail -1)
if [ -z "$first_move_line" ] || [ -z "$end_line" ] || [ -z "$ok_move_line" ] || [ "$first_move_line" -ge "$end_line" ] || [ "$end_line" -ge "$ok_move_line" ]; then
    echo "mir loan liveness: first use must keep loan live; last use must end it" >&2
    cat "$work/multiple_use.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-loan-liveness "$work/branch_join_use.s" "$work/branch_join_use.mir"
branch_move_line=$(grep -Fn 'mir-error move of borrowed place Field(_1, 0)' "$work/branch_join_use.mir" | cut -d: -f1 | head -1)
branch_end_line=$(grep -Fn 'EndBorrow(p, Field(_1, 0))' "$work/branch_join_use.mir" | cut -d: -f1 | head -1)
branch_ok_line=$(grep -Fn 'Move(Field(_1, 0)) OK' "$work/branch_join_use.mir" | cut -d: -f1 | tail -1)
if [ -z "$branch_move_line" ] || [ -z "$branch_end_line" ] || [ -z "$branch_ok_line" ] || [ "$branch_move_line" -ge "$branch_end_line" ] || [ "$branch_end_line" -ge "$branch_ok_line" ]; then
    echo "mir loan liveness: branch-local use must not end loan before join use" >&2
    cat "$work/branch_join_use.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-loan-liveness "$work/two_refs_same_place.s" "$work/two_refs_same_place.mir"
if ! grep -Fq 'EndBorrow(p, Field(_1, 0))' "$work/two_refs_same_place.mir"; then
    echo "mir loan liveness: first shared ref should end independently" >&2
    cat "$work/two_refs_same_place.mir" >&2
    exit 1
fi
if ! grep -Fq 'EndBorrow(q, Field(_1, 0))' "$work/two_refs_same_place.mir"; then
    echo "mir loan liveness: second shared ref should end independently" >&2
    cat "$work/two_refs_same_place.mir" >&2
    exit 1
fi
if ! grep -Fq 'mir-error move of borrowed place Field(_1, 0)' "$work/two_refs_same_place.mir"; then
    echo "mir loan liveness: remaining sibling loan should still block move" >&2
    cat "$work/two_refs_same_place.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-loan-liveness "$work/sibling_place.s" "$work/sibling_place.mir"
if ! grep -Fq 'Move(Field(_1, 1)) OK' "$work/sibling_place.mir"; then
    echo "mir loan liveness: sibling place should not be blocked by live loan" >&2
    cat "$work/sibling_place.mir" >&2
    exit 1
fi
if ! grep -Fq 'Move(Field(_1, 0)) OK' "$work/sibling_place.mir"; then
    echo "mir loan liveness: borrowed place should move after last use ends loan" >&2
    cat "$work/sibling_place.mir" >&2
    exit 1
fi

echo "MIR loan liveness check passed"
