#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-place.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

cat >"$work/place.s" <<'SRC'
package place

func main() int {
    local _1
    field _1 0
    nested_field _1 0 1
    deref_place _2
    index_place _3 _4
    return 0
}
SRC

"$root/bin/s" --emit-mir-place "$work/place.s" "$work/place.mir"

for expected in \
    'Local(_1)' \
    'Field(_1, 0)' \
    'Field(Field(_1, 0), 1)' \
    'Deref(_2)' \
    'Index(_3, _4)'
do
    if ! grep -q "$expected" "$work/place.mir"; then
        echo "mir place: expected $expected" >&2
        cat "$work/place.mir" >&2
        exit 1
    fi
done

echo "MIR place check passed"
