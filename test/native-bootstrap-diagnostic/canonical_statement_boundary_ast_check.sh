#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-canonical-boundary-ast.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
import ("compile.internal.syntax"; "compile.internal.ast")
func negative(compile.internal.ast.expr expression) bool {
    switch expression {
        expr.binary(binary): {
            if binary.op != "-" { return false }
            zero := false
            one := false
            switch binary.left.value { expr.int(n): zero = n.value == "0", _: (), }
            switch binary.right.value { expr.int(n): one = n.value == "1", _: (), }
            return zero && one
        },
        _: return false,
    }
}
func independent(compile.internal.ast.stmt statement, string kind) bool {
    switch statement {
        stmt.expr(v): { switch v.expr { expr.if(_): return kind == "if", expr.for(_): return kind == "for", expr.while(_): return kind == "while", expr.switch(_): return kind == "switch", expr.block(_): return kind == "block", _: return false, } },
        _: return false,
    }
}
func check_body(compile.internal.ast.block_expr body, string kind) () {
    if len(body.statements) != 1 || body.final_expr.is_none() { panic("if statement consumed the negative tail") }
    if !independent(body.statements[0], kind) { panic("missing independent if statement") }
    if !negative(body.final_expr.unwrap()) { panic("negative tail is not unary minus of one") }
}
func check_kind(string body_text, string kind) () {
    source := "package main\nfunc read(int input) int {\n" + body_text + "\n}\n"
    parsed, error := compile.internal.syntax.parse_source(source)
    if error.message != "" { panic(error.message) }
    switch parsed.items[0] { item.function(declaration): check_body(declaration.body.unwrap(), kind), _: panic("missing function"), }
}
func check(string body_text) () { check_kind(body_text, "if") }
func main() int {
    check("if input > 0 { return input }\n-1")
    check("if input > 0 { return input }\r\n-1")
    check("if input > 0 { return input } // tail follows\n-1")
    check("if input > 0 { return input } /* comment\ncontinued */ -1")
    check("if input > 0 { return input }\nelse if input < 0 { return 1 }\n-1")
    check("if input > 0 { return input }; -1")
    check_kind("for input > 0 { return input }\n-1", "for")
    check_kind("while input > 0 { return input }\n-1", "while")
    check_kind("switch input { 0: (), _: (), }\n-1", "switch")
    check_kind("{ local := input }\n-1", "block")
    return 42
}
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$root/src/option/option.s" "$root/src/result/result.s" "$root/src/prelude/prelude.s" "$root/src/fs/fs.s" "$root/src/cmd/compile/internal/ast/ast.s" "$root/src/cmd/compile/internal/parser/syntax/syntax.s" "$root/src/cmd/compile/internal/parser/syntax/canonical_parser.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'canonical statement boundary AST: independent control statements and unary negative tail, comments, CRLF and else-chain: PASS'
