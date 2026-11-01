#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-ast-param.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "AST parameter artifacts: $work" >&2; fi' EXIT
cat > "$work/main.s" <<'S'
package main
func main() int {
    p := compile.internal.ast.param { name: "value", type_name: "int" }
    f := compile.internal.ast.function_decl {
        sig: compile.internal.ast.function_sig { name: "answer", params: [p], return_type: std.option.none },
        body: std.option.none,
    }
    lines := compile.internal.ast.dump_function(f, "")
    if len(lines) != 1 { return 1 }
    if lines[0] != "func answer(int value)" { return 2 }
    f.is_public = true
    public_lines := compile.internal.ast.dump_function(f, "")
    if public_lines[0] != "pub func answer(int value)" { return 3 }
    return 42
}
S
"$root/bin/s_seed" --compile-native-unit "$work/ast.ir" "$root/src/prelude/prelude.s" "$root/src/option/option.s" "$root/src/cmd/compile/internal/ast/ast.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/ast.ir" "$work/ast"
status=0; timeout 15 "$work/ast" || status=$?; test "$status" -eq 42
echo 'production AST function dump reads declared parameter types: PASS'
