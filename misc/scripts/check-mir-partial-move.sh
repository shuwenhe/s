#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-partial-move.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

cat >"$work/field_partial.s" <<'SRC'
package partialmove
func main() int {
    move_field _1 0
    use_field _1 1
    use_field _1 0
    use_local _1
    return 0
}
SRC

cat >"$work/nested_partial.s" <<'SRC'
package partialmove
func main() int {
    move_nested_field _1 0 1
    use_nested_field _1 0 0
    use_field _1 1
    use_nested_field _1 0 1
    use_field _1 0
    use_local _1
    return 0
}
SRC

"$root/bin/s" --emit-mir-partial-move "$work/field_partial.s" "$work/field_partial.mir"
for expected in \
    'Use(Field(_1, 1)) OK' \
    'mir-error use of moved place Field(_1, 0)' \
    'mir-error use of partially moved place Local(_1)'
do
    if ! grep -Fq "$expected" "$work/field_partial.mir"; then
        echo "mir partial move: expected field partial behavior: $expected" >&2
        cat "$work/field_partial.mir" >&2
        exit 1
    fi
done

"$root/bin/s" --emit-mir-partial-move "$work/nested_partial.s" "$work/nested_partial.mir"
for expected in \
    'Use(Field(Field(_1, 0), 0)) OK' \
    'Use(Field(_1, 1)) OK' \
    'mir-error use of moved place Field(Field(_1, 0), 1)' \
    'mir-error use of partially moved place Field(_1, 0)' \
    'mir-error use of partially moved place Local(_1)'
do
    if ! grep -Fq "$expected" "$work/nested_partial.mir"; then
        echo "mir partial move: expected nested partial behavior: $expected" >&2
        cat "$work/nested_partial.mir" >&2
        exit 1
    fi
done

echo "MIR partial move check passed"
