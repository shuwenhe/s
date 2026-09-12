#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-nll-own.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

cat >"$work/sibling_and_borrowed.s" <<'SRC'
package nllown
func main() int {
    borrow_shared_field p _1 0
    move_field _1 1
    move_field _1 0
    drop _1
    return 0
}
SRC

cat >"$work/partial_drop_after_last_use.s" <<'SRC'
package nllown
func main() int {
    borrow_shared_field p _1 0
    use_ref p
    move_field _1 0
    drop _1
    return 0
}
SRC

cat >"$work/reinit_whole_drop.s" <<'SRC'
package nllown
func main() int {
    borrow_mut_field p _1 0
    use_ref p
    move_field _1 0
    assign_field _1 0
    drop _1
    return 0
}
SRC

cat >"$work/alias_chain.s" <<'SRC'
package nllown
func main() int {
    borrow_shared_field p _1 0
    q := p
    r := q
    move_field _1 0
    use_ref r
    move_field _1 0
    drop _1
    return 0
}
SRC

"$root/bin/s" --emit-mir-nll-ownership "$work/sibling_and_borrowed.s" "$work/sibling_and_borrowed.mir"
for expected in \
    'Move(Field(_1, 1)) at P1 OK' \
    'mir-error nll move of borrowed place Field(_1, 0) at P2' \
    'Drop(Field(_1, 0))'
do
    if ! grep -Fq "$expected" "$work/sibling_and_borrowed.mir"; then
        echo "mir nll ownership: sibling move and borrowed field conflict failed: $expected" >&2
        cat "$work/sibling_and_borrowed.mir" >&2
        exit 1
    fi
done
if grep -Fq 'Drop(Local(_1))' "$work/sibling_and_borrowed.mir"; then
    echo "mir nll ownership: partial move must not whole-drop" >&2
    cat "$work/sibling_and_borrowed.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-nll-ownership "$work/partial_drop_after_last_use.s" "$work/partial_drop_after_last_use.mir"
for expected in \
    'Move(Field(_1, 0)) at P2 OK' \
    'Drop(Field(_1, 1))'
do
    if ! grep -Fq "$expected" "$work/partial_drop_after_last_use.mir"; then
        echo "mir nll ownership: last-use move should lead to partial drop: $expected" >&2
        cat "$work/partial_drop_after_last_use.mir" >&2
        exit 1
    fi
done
for forbidden in 'Drop(Local(_1))' 'Drop(Field(_1, 0))'; do
    if grep -Fq "$forbidden" "$work/partial_drop_after_last_use.mir"; then
        echo "mir nll ownership: moved field/whole object dropped incorrectly: $forbidden" >&2
        cat "$work/partial_drop_after_last_use.mir" >&2
        exit 1
    fi
done

"$root/bin/s" --emit-mir-nll-ownership "$work/reinit_whole_drop.s" "$work/reinit_whole_drop.mir"
for expected in \
    'Move(Field(_1, 0)) at P2 OK' \
    'Assign(Field(_1, 0)) OK' \
    'Drop(Local(_1))'
do
    if ! grep -Fq "$expected" "$work/reinit_whole_drop.mir"; then
        echo "mir nll ownership: reinit should restore whole drop: $expected" >&2
        cat "$work/reinit_whole_drop.mir" >&2
        exit 1
    fi
done

"$root/bin/s" --emit-mir-nll-ownership "$work/alias_chain.s" "$work/alias_chain.mir"
for expected in \
    'mir-error nll move of borrowed place Field(_1, 0) at P3' \
    'Move(Field(_1, 0)) at P5 OK' \
    'Drop(Field(_1, 1))'
do
    if ! grep -Fq "$expected" "$work/alias_chain.mir"; then
        echo "mir nll ownership: alias chain should integrate with move/drop: $expected" >&2
        cat "$work/alias_chain.mir" >&2
        exit 1
    fi
done

echo "MIR NLL ownership check passed"
