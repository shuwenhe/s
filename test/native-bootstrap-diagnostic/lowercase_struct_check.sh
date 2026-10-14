#!/bin/sh
set -eu

ROOT=${S_SOURCE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
WORK="$ROOT/.bootstrap/lowercase-struct-check"
mkdir -p "$WORK"

cd "$ROOT"

make seed-compiler-bin >/dev/null

cat >"$WORK/lowercase_struct.s" <<'SRC'
package main

struct compiler_state {
    count int
}

func make_state(int value) compiler_state {
    return compiler_state(value)
}

func main() int {
    state := make_state(7)
    return state.count
}
SRC

cat >"$WORK/undefined_type.s" <<'SRC'
package main

struct holder {
    value missing_type
}

func main() int {
    return 0
}
SRC

S_SOURCE_ROOT="$ROOT" "$ROOT/src/cmd/dist/source_closure.sh" \
    src/cmd/compile/main.s "$WORK/stage1.sources"

"$ROOT/bin/s_seed" --compile-unit "$WORK/stage1.ir" \
    $(sed "s#^#$ROOT/#" "$WORK/stage1.sources") >/dev/null
"$ROOT/bin/s_seed" --emit-bin "$WORK/stage1.ir" "$WORK/stage1" >/dev/null
chmod +x "$WORK/stage1"

if "$WORK/stage1" --compile-unit "$WORK/lowercase_struct.ir" "$WORK/lowercase_struct.s" \
    >"$WORK/lowercase_struct.log" 2>&1; then
    :
else
    cat "$WORK/lowercase_struct.log" >&2
    exit 1
fi

test -s "$WORK/lowercase_struct.ir" || {
    echo "lowercase struct check: missing output" >&2
    exit 1
}

grep -q 'S_compiler_state' "$WORK/lowercase_struct.ir" || {
    echo "lowercase struct check: output does not preserve lowercase struct type" >&2
    exit 1
}

if "$WORK/stage1" --compile-unit "$WORK/undefined_type.ir" "$WORK/undefined_type.s" \
    >"$WORK/undefined_type.log" 2>&1; then
    echo "lowercase struct check: undefined struct type unexpectedly compiled" >&2
    exit 1
fi

grep -q 'unknown struct field type: missing_type' "$WORK/undefined_type.log" || {
    cat "$WORK/undefined_type.log" >&2
    exit 1
}
