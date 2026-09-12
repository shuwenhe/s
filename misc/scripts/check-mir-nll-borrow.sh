#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-nll-borrow.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

cat >"$work/alias_chain_conflict.s" <<'SRC'
package nll
func main() int {
    borrow_mut_field p _1 0
    q := p
    r := q
    move_field _1 0
    use_ref r
    move_field _1 0
    return 0
}
SRC

cat >"$work/sibling_ok.s" <<'SRC'
package nll
func main() int {
    borrow_shared_field p _1 0
    q := p
    move_field _1 1
    use_ref q
    move_field _1 0
    return 0
}
SRC

cat >"$work/diamond_conflict.s" <<'SRC'
package nll
func main() int {
    borrow_shared_field p _1 0
    q := p
    r := p
    s := q
    move_field _1 0
    use_ref s
    use_ref r
    move_field _1 0
    return 0
}
SRC

"$root/bin/s" --emit-mir-nll-borrow-check "$work/alias_chain_conflict.s" "$work/alias_chain_conflict.mir"
for expected in \
    'Loan(L0) = {P0, P4}' \
    'mir-error nll move of borrowed place Field(_1, 0) at P3' \
    'Move(Field(_1, 0)) at P5 OK' \
    'NLLBorrowCheck(iterations=' \
    'converged=true)'
do
    if ! grep -Fq "$expected" "$work/alias_chain_conflict.mir"; then
        echo "mir nll borrow: alias chain should drive move conflict from solved loan points: $expected" >&2
        cat "$work/alias_chain_conflict.mir" >&2
        exit 1
    fi
done

"$root/bin/s" --emit-mir-nll-borrow-check "$work/sibling_ok.s" "$work/sibling_ok.mir"
if ! grep -Fq 'Move(Field(_1, 1)) at P2 OK' "$work/sibling_ok.mir"; then
    echo "mir nll borrow: sibling place should not conflict with live loan" >&2
    cat "$work/sibling_ok.mir" >&2
    exit 1
fi
if ! grep -Fq 'Move(Field(_1, 0)) at P4 OK' "$work/sibling_ok.mir"; then
    echo "mir nll borrow: borrowed place should move after solved loan lifetime ends" >&2
    cat "$work/sibling_ok.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-nll-borrow-check "$work/diamond_conflict.s" "$work/diamond_conflict.mir"
for expected in \
    'Loan(L0) = {P0, P5, P6}' \
    'mir-error nll move of borrowed place Field(_1, 0) at P4' \
    'Move(Field(_1, 0)) at P7 OK'
do
    if ! grep -Fq "$expected" "$work/diamond_conflict.mir"; then
        echo "mir nll borrow: diamond region solution should feed conflict checker: $expected" >&2
        cat "$work/diamond_conflict.mir" >&2
        exit 1
    fi
done

echo "MIR NLL borrow check passed"
