#!/bin/sh
set -eu

ROOT=${S_SOURCE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
WORK="$ROOT/.bootstrap/extern-decl-check"
mkdir -p "$WORK"

cd "$ROOT"

make seed-compiler-bin >/dev/null

cat >"$WORK/extern_input.s" <<'SRC'
package main
extern "intrinsic" func host_write(string text) int;

func main() int {
    return host_write("hello")
}
SRC

S_SOURCE_ROOT="$ROOT" "$ROOT/src/cmd/dist/source_closure.sh" \
    src/cmd/compile/main.s "$WORK/stage1.sources"

"$ROOT/bin/s_seed" --compile-unit "$WORK/stage1.ir" \
    $(sed "s#^#$ROOT/#" "$WORK/stage1.sources") >/dev/null
"$ROOT/bin/s_seed" --emit-bin "$WORK/stage1.ir" "$WORK/stage1" >/dev/null
chmod +x "$WORK/stage1"

if "$WORK/stage1" --compile-unit "$WORK/extern_output.ir" "$WORK/extern_input.s" \
    >"$WORK/extern.log" 2>&1; then
    :
else
    cat "$WORK/extern.log" >&2
    exit 1
fi

test -s "$WORK/extern_output.ir" || {
    echo "extern decl check: missing output" >&2
    exit 1
}

grep -q 'host_write' "$WORK/extern_output.ir" || {
    echo "extern decl check: output does not preserve extern call" >&2
    exit 1
}
