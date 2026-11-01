#!/bin/sh
set -eu

ROOT=${S_SOURCE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
WORK="$ROOT/.bootstrap/type-first-struct-field-check"
mkdir -p "$WORK"

cd "$ROOT"

make seed-compiler-bin >/dev/null

cat >"$WORK/type_first.s" <<'SRC'
package main

struct compiler_state {
    string source
    int pos
}

func main() int {
    state := compiler_state("abc", 3)
    return state.pos
}
SRC

cat >"$WORK/name_first.s" <<'SRC'
package main

struct CompilerState {
    source string
    pos int
}

func main() int {
    state := CompilerState("abc", 3)
    return state.pos
}
SRC

cat >"$WORK/custom_type.s" <<'SRC'
package main

struct inner {
    int value
}

struct outer {
    inner item
}

func main() int {
    obj := outer(inner(4))
    return obj.item.value
}
SRC

cat >"$WORK/undefined_type.s" <<'SRC'
package main

struct holder {
    missing_type value
}

func main() int {
    return 0
}
SRC

cat >"$WORK/duplicate_field.s" <<'SRC'
package main

struct duplicate {
    int value
    string value
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

for case_name in type_first name_first custom_type; do
    if "$WORK/stage1" --compile-unit "$WORK/${case_name}.ir" "$WORK/${case_name}.s" \
        >"$WORK/${case_name}.log" 2>&1; then
        :
    else
        cat "$WORK/${case_name}.log" >&2
        exit 1
    fi
    test -s "$WORK/${case_name}.ir" || {
        echo "type-first struct field check: missing output for $case_name" >&2
        exit 1
    }
done

grep -q 'S_compiler_state' "$WORK/type_first.ir" || {
    echo "type-first struct field check: missing lowercase type in IR" >&2
    exit 1
}
grep -q 'source' "$WORK/type_first.ir" || {
    echo "type-first struct field check: missing source field in IR" >&2
    exit 1
}
grep -q 'pos' "$WORK/type_first.ir" || {
    echo "type-first struct field check: missing pos field in IR" >&2
    exit 1
}

if "$WORK/stage1" --compile-unit "$WORK/undefined_type.ir" "$WORK/undefined_type.s" \
    >"$WORK/undefined_type.log" 2>&1; then
    echo "type-first struct field check: undefined field type unexpectedly compiled" >&2
    exit 1
fi
grep -q 'missing_type' "$WORK/undefined_type.log" || {
    cat "$WORK/undefined_type.log" >&2
    exit 1
}

if "$WORK/stage1" --compile-unit "$WORK/duplicate_field.ir" "$WORK/duplicate_field.s" \
    >"$WORK/duplicate_field.log" 2>&1; then
    echo "type-first struct field check: duplicate field unexpectedly compiled" >&2
    exit 1
fi
grep -q 'struct fields must have distinct names' "$WORK/duplicate_field.log" || {
    cat "$WORK/duplicate_field.log" >&2
    exit 1
}
