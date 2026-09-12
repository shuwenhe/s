#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-movepath.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

cat >"$work/field_move.s" <<'SRC'
package movepath
func main() int {
    move_field _1 0
    return 0
}
SRC

cat >"$work/nested_move.s" <<'SRC'
package movepath
func main() int {
    move_nested_field _1 0 1
    return 0
}
SRC

cat >"$work/local_move.s" <<'SRC'
package movepath
func main() int {
    move_local _1
    return 0
}
SRC

"$root/bin/s" --emit-mir-movepath "$work/field_move.s" "$work/field_move.mir"
for expected in \
    'MovePath(place=Local(_1), parent=none, children=[Field(_1,0),Field(_1,1)], state=PARTIALLY_MOVED)' \
    'MovePath(place=Field(_1,0), parent=0, children=[Field(Field(_1,0),0),Field(Field(_1,0),1)], state=MOVED)' \
    'MovePath(place=Field(_1,1), parent=0, children=[], state=LIVE)'
do
    if ! grep -Fq "$expected" "$work/field_move.mir"; then
        echo "mir movepath: expected field move state: $expected" >&2
        cat "$work/field_move.mir" >&2
        exit 1
    fi
done

"$root/bin/s" --emit-mir-movepath "$work/nested_move.s" "$work/nested_move.mir"
for expected in \
    'MovePath(place=Local(_1), parent=none, children=[Field(_1,0),Field(_1,1)], state=PARTIALLY_MOVED)' \
    'MovePath(place=Field(_1,0), parent=0, children=[Field(Field(_1,0),0),Field(Field(_1,0),1)], state=PARTIALLY_MOVED)' \
    'MovePath(place=Field(Field(_1,0),1), parent=1, children=[], state=MOVED)' \
    'MovePath(place=Field(Field(_1,0),0), parent=1, children=[], state=LIVE)' \
    'MovePath(place=Field(_1,1), parent=0, children=[], state=LIVE)'
do
    if ! grep -Fq "$expected" "$work/nested_move.mir"; then
        echo "mir movepath: expected nested move state: $expected" >&2
        cat "$work/nested_move.mir" >&2
        exit 1
    fi
done

"$root/bin/s" --emit-mir-movepath "$work/local_move.s" "$work/local_move.mir"
if grep -q 'state=LIVE' "$work/local_move.mir" || grep -q 'state=PARTIALLY_MOVED' "$work/local_move.mir"; then
    echo "mir movepath: whole local move should recursively mark all paths MOVED" >&2
    cat "$work/local_move.mir" >&2
    exit 1
fi
if [ "$(grep -c 'state=MOVED' "$work/local_move.mir" || true)" -lt 5 ]; then
    echo "mir movepath: expected all move paths to become MOVED" >&2
    cat "$work/local_move.mir" >&2
    exit 1
fi

echo "MIR movepath check passed"
