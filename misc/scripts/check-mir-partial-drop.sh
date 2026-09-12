#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-partial-drop.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

cat >"$work/live_local.s" <<'SRC'
package partialdrop
func main() int {
    return 0
}
SRC

cat >"$work/field_partial.s" <<'SRC'
package partialdrop
func main() int {
    move_field _1 0
    return 0
}
SRC

cat >"$work/nested_partial.s" <<'SRC'
package partialdrop
func main() int {
    move_nested_field _1 0 1
    return 0
}
SRC

cat >"$work/reinit_whole.s" <<'SRC'
package partialdrop
func main() int {
    move_nested_field _1 0 1
    assign_nested_field _1 0 1
    return 0
}
SRC

cat >"$work/moved_local.s" <<'SRC'
package partialdrop
func main() int {
    move_local _1
    return 0
}
SRC

"$root/bin/s" --emit-mir-partial-drop "$work/live_local.s" "$work/live_local.mir"
if ! grep -Fq 'Drop(Local(_1))' "$work/live_local.mir"; then
    echo "mir partial drop: live whole object should drop Local(_1)" >&2
    cat "$work/live_local.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-partial-drop "$work/field_partial.s" "$work/field_partial.mir"
if ! grep -Fq 'Drop(Field(_1, 1))' "$work/field_partial.mir"; then
    echo "mir partial drop: field partial move should drop remaining live sibling" >&2
    cat "$work/field_partial.mir" >&2
    exit 1
fi
for forbidden in 'Drop(Local(_1))' 'Drop(Field(_1, 0))'; do
    if grep -Fq "$forbidden" "$work/field_partial.mir"; then
        echo "mir partial drop: field partial move emitted invalid drop: $forbidden" >&2
        cat "$work/field_partial.mir" >&2
        exit 1
    fi
done

"$root/bin/s" --emit-mir-partial-drop "$work/nested_partial.s" "$work/nested_partial.mir"
for expected in 'Drop(Field(_1, 1))' 'Drop(Field(Field(_1, 0), 0))'; do
    if ! grep -Fq "$expected" "$work/nested_partial.mir"; then
        echo "mir partial drop: nested partial move missed live drop: $expected" >&2
        cat "$work/nested_partial.mir" >&2
        exit 1
    fi
done
for forbidden in 'Drop(Local(_1))' 'Drop(Field(_1, 0))' 'Drop(Field(Field(_1, 0), 1))'; do
    if grep -Fq "$forbidden" "$work/nested_partial.mir"; then
        echo "mir partial drop: nested partial move emitted invalid drop: $forbidden" >&2
        cat "$work/nested_partial.mir" >&2
        exit 1
    fi
done
drop_f1_line=$(grep -Fn 'Drop(Field(_1, 1))' "$work/nested_partial.mir" | cut -d: -f1 | head -1)
drop_f00_line=$(grep -Fn 'Drop(Field(Field(_1, 0), 0))' "$work/nested_partial.mir" | cut -d: -f1 | head -1)
if [ -z "$drop_f1_line" ] || [ -z "$drop_f00_line" ] || [ "$drop_f1_line" -ge "$drop_f00_line" ]; then
    echo "mir partial drop: nested partial drops should keep reverse field order" >&2
    cat "$work/nested_partial.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-partial-drop "$work/reinit_whole.s" "$work/reinit_whole.mir"
if ! grep -Fq 'Drop(Local(_1))' "$work/reinit_whole.mir"; then
    echo "mir partial drop: reinitialized object should become whole-live again" >&2
    cat "$work/reinit_whole.mir" >&2
    exit 1
fi
if grep -Fq 'Drop(Field(' "$work/reinit_whole.mir"; then
    echo "mir partial drop: whole-live reinitialized object should not field-drop" >&2
    cat "$work/reinit_whole.mir" >&2
    exit 1
fi

"$root/bin/s" --emit-mir-partial-drop "$work/moved_local.s" "$work/moved_local.mir"
if grep -Fq 'Drop(' "$work/moved_local.mir"; then
    echo "mir partial drop: moved whole object should not drop anything" >&2
    cat "$work/moved_local.mir" >&2
    exit 1
fi

echo "MIR partial drop check passed"
