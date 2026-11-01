#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-place-borrow.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

cat >"$work/sibling_shared_mut.s" <<'SRC'
package placeborrow
func main() int {
    borrow_shared_field _1 0
    borrow_mut_field _1 1
    return 0
}
SRC

cat >"$work/same_shared_shared.s" <<'SRC'
package placeborrow
func main() int {
    borrow_shared_field _1 0
    borrow_shared_field _1 0
    return 0
}
SRC

cat >"$work/same_shared_mut.s" <<'SRC'
package placeborrow
func main() int {
    borrow_shared_field _1 0
    borrow_mut_field _1 0
    return 0
}
SRC

cat >"$work/same_mut_shared.s" <<'SRC'
package placeborrow
func main() int {
    borrow_mut_field _1 0
    borrow_shared_field _1 0
    return 0
}
SRC

cat >"$work/ancestor_descendant.s" <<'SRC'
package placeborrow
func main() int {
    borrow_shared_field _1 0
    borrow_mut_nested_field _1 0 1
    return 0
}
SRC

cat >"$work/descendant_ancestor.s" <<'SRC'
package placeborrow
func main() int {
    borrow_mut_nested_field _1 0 1
    borrow_shared_field _1 0
    return 0
}
SRC

cat >"$work/nested_siblings.s" <<'SRC'
package placeborrow
func main() int {
    borrow_shared_nested_field _1 0 0
    borrow_mut_nested_field _1 0 1
    return 0
}
SRC

cat >"$work/local_overlaps_field.s" <<'SRC'
package placeborrow
func main() int {
    borrow_shared_local _1
    borrow_mut_field _1 1
    return 0
}
SRC

"$root/bin/s" --emit-mir-place-borrow "$work/sibling_shared_mut.s" "$work/sibling_shared_mut.mir"
for expected in \
    'Borrow(shared, Field(_1, 0)) OK' \
    'Borrow(mut, Field(_1, 1)) OK'
do
    if ! grep -Fq "$expected" "$work/sibling_shared_mut.mir"; then
        echo "mir place borrow: sibling field borrow should be allowed: $expected" >&2
        cat "$work/sibling_shared_mut.mir" >&2
        exit 1
    fi
done

"$root/bin/s" --emit-mir-place-borrow "$work/same_shared_shared.s" "$work/same_shared_shared.mir"
if [ "$(grep -Fc 'Borrow(shared, Field(_1, 0)) OK' "$work/same_shared_shared.mir" || true)" -ne 2 ]; then
    echo "mir place borrow: repeated shared borrow of same place should be allowed" >&2
    cat "$work/same_shared_shared.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-place-borrow "$work/same_shared_mut.s" "$work/same_shared_mut.mir"
if ! grep -Fq 'mir-error mutable borrow while shared borrowed Field(_1, 0)' "$work/same_shared_mut.mir"; then
    echo "mir place borrow: mutable borrow of shared same place should be rejected" >&2
    cat "$work/same_shared_mut.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-place-borrow "$work/same_mut_shared.s" "$work/same_mut_shared.mir"
if ! grep -Fq 'mir-error shared borrow while mutably borrowed Field(_1, 0)' "$work/same_mut_shared.mir"; then
    echo "mir place borrow: shared borrow of mutably borrowed same place should be rejected" >&2
    cat "$work/same_mut_shared.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-place-borrow "$work/ancestor_descendant.s" "$work/ancestor_descendant.mir"
if ! grep -Fq 'mir-error mutable borrow while shared borrowed Field(Field(_1, 0), 1)' "$work/ancestor_descendant.mir"; then
    echo "mir place borrow: mutable descendant borrow should conflict with shared ancestor" >&2
    cat "$work/ancestor_descendant.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-place-borrow "$work/descendant_ancestor.s" "$work/descendant_ancestor.mir"
if ! grep -Fq 'mir-error shared borrow while mutably borrowed Field(_1, 0)' "$work/descendant_ancestor.mir"; then
    echo "mir place borrow: shared ancestor borrow should conflict with mutable descendant" >&2
    cat "$work/descendant_ancestor.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-place-borrow "$work/nested_siblings.s" "$work/nested_siblings.mir"
for expected in \
    'Borrow(shared, Field(Field(_1, 0), 0)) OK' \
    'Borrow(mut, Field(Field(_1, 0), 1)) OK'
do
    if ! grep -Fq "$expected" "$work/nested_siblings.mir"; then
        echo "mir place borrow: nested sibling borrow should be allowed: $expected" >&2
        cat "$work/nested_siblings.mir" >&2
        exit 1
    fi
done

"$root/bin/s" --emit-mir-place-borrow "$work/local_overlaps_field.s" "$work/local_overlaps_field.mir"
if ! grep -Fq 'mir-error mutable borrow while shared borrowed Field(_1, 1)' "$work/local_overlaps_field.mir"; then
    echo "mir place borrow: whole-object borrow should overlap field borrow" >&2
    cat "$work/local_overlaps_field.mir" >&2
    exit 1
fi

echo "MIR place borrow check passed"
