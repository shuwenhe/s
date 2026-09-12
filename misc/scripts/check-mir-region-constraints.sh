#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-region.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

cat >"$work/alias_extends_loan.s" <<'SRC'
package region
func main() int {
    borrow_mut_field p _1 0
    q := p
    move_field _1 0
    use_ref q
    move_field _1 0
    return 0
}
SRC

cat >"$work/direct_use_constraints.s" <<'SRC'
package region
func main() int {
    borrow_shared_field p _1 0
    use_ref p
    move_field _1 0
    return 0
}
SRC

cat >"$work/branch_join_alias.s" <<'SRC'
package region
func main() int {
    borrow_shared_field p _1 0
    if cond {
        q := p
        use_ref q
    } else {
    }
    move_field _1 0
    use_ref p
    move_field _1 0
    return 0
}
SRC

cat >"$work/sibling_place.s" <<'SRC'
package region
func main() int {
    borrow_shared_field p _1 0
    q := p
    move_field _1 1
    use_ref q
    move_field _1 0
    return 0
}
SRC

"$root/bin/s" --emit-mir-region-constraints "$work/alias_extends_loan.s" "$work/alias_extends_loan.mir"
for expected in \
    'p = Borrow(L0, Field(_1, 0))' \
    'q = Alias(p, L0)' \
    "outlives('r_p, 'r_q)" \
    'UseRef(q, L0)' \
    'EndBorrow(L0, Field(_1, 0))'
do
    if ! grep -Fq "$expected" "$work/alias_extends_loan.mir"; then
        echo "mir region constraints: missing alias constraint behavior: $expected" >&2
        cat "$work/alias_extends_loan.mir" >&2
        exit 1
    fi
done
alias_bad_line=$(grep -Fn 'mir-error move of region-live borrowed place Field(_1, 0)' "$work/alias_extends_loan.mir" | cut -d: -f1 | head -1)
alias_end_line=$(grep -Fn 'EndBorrow(L0, Field(_1, 0))' "$work/alias_extends_loan.mir" | cut -d: -f1 | head -1)
alias_ok_line=$(grep -Fn 'Move(Field(_1, 0)) OK' "$work/alias_extends_loan.mir" | cut -d: -f1 | tail -1)
if [ -z "$alias_bad_line" ] || [ -z "$alias_end_line" ] || [ -z "$alias_ok_line" ] || [ "$alias_bad_line" -ge "$alias_end_line" ] || [ "$alias_end_line" -ge "$alias_ok_line" ]; then
    echo "mir region constraints: alias q must keep original loan live until q last use" >&2
    cat "$work/alias_extends_loan.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-region-constraints "$work/direct_use_constraints.s" "$work/direct_use_constraints.mir"
for expected in \
    'loan_live_at(L0, P0)' \
    "region_contains('r_p, P0)" \
    'UseRef(p, L0)' \
    'loan_live_at(L0, P1)' \
    "region_contains('r_p, P1)"
do
    if ! grep -Fq "$expected" "$work/direct_use_constraints.mir"; then
        echo "mir region constraints: missing direct region constraint: $expected" >&2
        cat "$work/direct_use_constraints.mir" >&2
        exit 1
    fi
done

"$root/bin/s" --emit-mir-region-constraints "$work/branch_join_alias.s" "$work/branch_join_alias.mir"
if ! grep -Fq 'q = Alias(p, L0)' "$work/branch_join_alias.mir"; then
    echo "mir region constraints: branch alias should still emit alias constraint" >&2
    cat "$work/branch_join_alias.mir" >&2
    exit 1
fi
branch_bad_line=$(grep -Fn 'mir-error move of region-live borrowed place Field(_1, 0)' "$work/branch_join_alias.mir" | cut -d: -f1 | head -1)
branch_end_line=$(grep -Fn 'EndBorrow(L0, Field(_1, 0))' "$work/branch_join_alias.mir" | cut -d: -f1 | head -1)
branch_ok_line=$(grep -Fn 'Move(Field(_1, 0)) OK' "$work/branch_join_alias.mir" | cut -d: -f1 | tail -1)
if [ -z "$branch_bad_line" ] || [ -z "$branch_end_line" ] || [ -z "$branch_ok_line" ] || [ "$branch_bad_line" -ge "$branch_end_line" ] || [ "$branch_end_line" -ge "$branch_ok_line" ]; then
    echo "mir region constraints: join use should keep loan live past branch-local alias use" >&2
    cat "$work/branch_join_alias.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-region-constraints "$work/sibling_place.s" "$work/sibling_place.mir"
if ! grep -Fq 'Move(Field(_1, 1)) OK' "$work/sibling_place.mir"; then
    echo "mir region constraints: sibling place should not conflict with region-live loan" >&2
    cat "$work/sibling_place.mir" >&2
    exit 1
fi
if ! grep -Fq 'Move(Field(_1, 0)) OK' "$work/sibling_place.mir"; then
    echo "mir region constraints: borrowed place should move after region loan ends" >&2
    cat "$work/sibling_place.mir" >&2
    exit 1
fi

echo "MIR region constraints check passed"
