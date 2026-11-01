#!/bin/sh
set -eu

ROOT=${S_SOURCE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
WORK="$ROOT/.bootstrap/ucp-syntax-probe-first-red"
PROBE_DIR="$WORK/src/cmd/compile/internal/ucp_probe"
mkdir -p "$PROBE_DIR"

cd "$ROOT"

make seed-compiler-bin >/dev/null

cat >"$PROBE_DIR/syntax_probe.s" <<'SRC'
package compile.internal.ucp_probe

import (
    "compile.internal.syntax"
)

func main() int {
    source := "package main\nfunc main() int { return 0 }\n"
    parsed := compile.internal.syntax.parse_source(source)
    if parsed.is_err() {
        return 1
    }
    return 0
}
SRC

S_SOURCE_ROOT="$ROOT" "$ROOT/src/cmd/dist/source_closure.sh" \
    .bootstrap/ucp-syntax-probe-first-red/src/cmd/compile/internal/ucp_probe/syntax_probe.s \
    "$WORK/syntax-probe.sources"

if "$ROOT/bin/s_seed" --compile-unit "$WORK/syntax-probe.ir" \
    $(sed "s#^#$ROOT/#" "$WORK/syntax-probe.sources") >"$WORK/seed.log" 2>&1; then
    echo "ucp syntax probe first-red check: expected Stage1 production syntax closure to fail, but it compiled" >&2
    exit 1
fi

if ! grep -Eq 'expected \{, got :=|expected member name, got NUMBER|PARSE_FAIL' "$WORK/seed.log"; then
    echo "ucp syntax probe first-red check: unexpected failure" >&2
    cat "$WORK/seed.log" >&2
    exit 1
fi

cat >"$WORK/first-red.txt" <<'EOF'
UCP-2 FIRST RED
stage=Stage1 production syntax probe
result=FAIL_EXPECTED
root_class=Stage1 cannot compile production parser dependency closure
evidence=seed compiler fails before probe binary exists
blocked_before=compile.internal.syntax.parse_source runtime execution
EOF

cat "$WORK/first-red.txt"
