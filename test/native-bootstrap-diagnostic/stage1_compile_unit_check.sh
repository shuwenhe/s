#!/bin/sh
set -eu

ROOT=${S_SOURCE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
WORK="$ROOT/.bootstrap/stage1-compile-unit-check"
mkdir -p "$WORK"

cd "$ROOT"

make seed-compiler-bin >/dev/null

S_SOURCE_ROOT="$ROOT" "$ROOT/src/cmd/dist/source_closure.sh" \
    src/cmd/compile/main.s "$WORK/stage1.sources"

if ! grep -qx 'src/cmd/compile/internal/compiler/frontend.s' "$WORK/stage1.sources"; then
    echo "stage1 compile-unit check: compiler frontend missing from source closure" >&2
    exit 1
fi

"$ROOT/bin/s_seed" --compile-unit "$WORK/stage1.ir" \
    $(sed "s#^#$ROOT/#" "$WORK/stage1.sources") >/dev/null
"$ROOT/bin/s_seed" --emit-bin "$WORK/stage1.ir" "$WORK/stage1" >/dev/null
chmod +x "$WORK/stage1"

if "$WORK/stage1" --compile-unit "$WORK/stage2.ir" \
    $(sed "s#^#$ROOT/#" "$WORK/stage1.sources") >"$WORK/stage1-compile-unit.log" 2>&1; then
    :
else
    cat "$WORK/stage1-compile-unit.log" >&2
    exit 1
fi

test -s "$WORK/stage2.ir" || {
    echo "stage1 compile-unit check: missing or empty stage2.ir" >&2
    exit 1
}

if grep -q 'not yet implemented' "$WORK/stage1-compile-unit.log"; then
    echo "stage1 compile-unit check: placeholder implementation reached" >&2
    exit 1
fi

if ! "$ROOT/bin/s_seed" --emit-bin "$WORK/stage2.ir" "$WORK/stage2" >"$WORK/stage2-emit.log" 2>&1; then
    cat "$WORK/stage2-emit.log" >&2
    exit 1
fi
