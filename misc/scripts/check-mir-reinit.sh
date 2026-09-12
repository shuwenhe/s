#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-reinit.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

cat >"$work/field_reinit.s" <<'SRC'
package reinit
func main() int {
    move_field _1 0
    use_local _1
    assign_field _1 0
    use_field _1 0
    use_local _1
    return 0
}
SRC

cat >"$work/nested_reinit.s" <<'SRC'
package reinit
func main() int {
    move_nested_field _1 0 1
    use_field _1 0
    assign_nested_field _1 0 1
    use_nested_field _1 0 1
    use_field _1 0
    use_local _1
    return 0
}
SRC

cat >"$work/incomplete_reinit.s" <<'SRC'
package reinit
func main() int {
    move_nested_field _1 0 1
    assign_nested_field _1 0 0
    use_field _1 0
    use_local _1
    return 0
}
SRC

"$root/bin/s" --emit-mir-reinit "$work/field_reinit.s" "$work/field_reinit.mir"
for expected in \
    'mir-error use of partially moved place Local(_1)' \
    'Use(Field(_1, 0)) OK' \
    'Use(Local(_1)) OK'
do
    if ! grep -Fq "$expected" "$work/field_reinit.mir"; then
        echo "mir reinit: expected field reinit behavior: $expected" >&2
        cat "$work/field_reinit.mir" >&2
        exit 1
    fi
done

"$root/bin/s" --emit-mir-reinit "$work/nested_reinit.s" "$work/nested_reinit.mir"
for expected in \
    'mir-error use of partially moved place Field(_1, 0)' \
    'Use(Field(Field(_1, 0), 1)) OK' \
    'Use(Field(_1, 0)) OK' \
    'Use(Local(_1)) OK'
do
    if ! grep -Fq "$expected" "$work/nested_reinit.mir"; then
        echo "mir reinit: expected nested reinit behavior: $expected" >&2
        cat "$work/nested_reinit.mir" >&2
        exit 1
    fi
done

"$root/bin/s" --emit-mir-reinit "$work/incomplete_reinit.s" "$work/incomplete_reinit.mir"
if ! grep -Fq 'mir-error use of partially moved place Field(_1, 0)' "$work/incomplete_reinit.mir"; then
    echo "mir reinit: incomplete nested reinit should keep parent partially moved" >&2
    cat "$work/incomplete_reinit.mir" >&2
    exit 1
fi
if ! grep -Fq 'mir-error use of partially moved place Local(_1)' "$work/incomplete_reinit.mir"; then
    echo "mir reinit: incomplete nested reinit should keep local partially moved" >&2
    cat "$work/incomplete_reinit.mir" >&2
    exit 1
fi

echo "MIR reinit check passed"
