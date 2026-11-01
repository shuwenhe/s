#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-const-option.XXXXXX)
trap 'rm -rf "$work"' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys
root,work=map(Path,sys.argv[1:])
text=(root/'src/cmd/compile/internal/semantic/semantic.s').read_text()
start=text.index('func no_const_expr('); end=text.index('\nfunc ',start+1)
(work/'helper.s').write_text('package compile.internal.semantic\nimport "std.option"\n'+text[start:end])
PY
cat > "$work/main.s" <<'S'
package main
func main() int {
    value := compile.internal.semantic.no_const_expr()
    if value.is_some() { return 1 }
    value = std.option.some(compile.internal.ast.expr.int(compile.internal.ast.int_expr {
        value: "42", inferred_type: std.option.none,
    }))
    if value.is_none() { return 2 }
    return 42
}
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$root/src/prelude/prelude.s" "$root/src/option/option.s" "$root/src/cmd/compile/internal/ast/ast.s" "$work/helper.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'production const-expression option starts none and accepts concrete AST expression: PASS'
