#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-ast-constructor.XXXXXX)
trap 'rm -rf "$work"' EXIT
# Execute the production helpers with competing IR record names in the unit.
# Unqualified constructors used to lose their schema and option field types.
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys
root, work = map(Path, sys.argv[1:])
helpers = []
for filename, name in [('program_payload.s', 'make_binary_expr'),
                       ('program_environment.s', 'program_replace_iota'),
                       ('program_environment.s', 'program_with_global_initializers'),
                       ('program_lower.s', 'program_item_package')]:
    source = (root / 'src/cmd/compile/internal/ir' / filename).read_text()
    start = source.index('func ' + name + '(')
    end = source.find('\nfunc ', start + 1)
    if name == 'make_binary_expr':
        end = source.index('\n// Payload enums', start)
    helpers.append(source[start:end])
(work / 'collision.s').write_text('package other.ast\nstruct binary_expr { int wrong }\nstruct param { int wrong }\n')
(work / 'main.s').write_text('''package compile.internal.ir.lower
import ("compile.internal.ast"; "std.option"; "std.prelude")
''' + '\n'.join(helpers) + '''
func main() int {
    left := expr.name(name_expr { name: "iota", inferred_type: option.none })
    right := expr.int(int_expr { value: "2", inferred_type: option.none })
    global := item.var(var_decl { name: "answer", type_name: option.some("int"), value: option.some(right) })
    source := source_file { pkg: "main", items: [global], item_packages: ["main"] }
    initialized := program_with_global_initializers(source)
    if len(initialized.items) != 2 { return 7 }
    switch initialized.items[1] {
        item.function(value): {
            if value.sig.name != "__global_init_answer" || len(value.sig.params) != 0 { return 8 }
            if value.sig.return_type.unwrap() != "int" || value.body.is_none() { return 9 }
        }
        _: return 10,
    }
    result := program_replace_iota(make_binary_expr(left, "+", right), 40)
    switch result {
        expr.binary(value): {
            if value.op != "+" || value.inferred_type.is_some() { return 1 }
            switch value.left.value {
                expr.int(number): { if number.value != "40" { return 2 } },
                _: return 3,
            }
            switch value.right.value {
                expr.int(number): { if number.value != "2" { return 4 } },
                _: return 5,
            }
            return 42
        }
        _: return 6,
    }
}
''')
PY
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" \
    "$root/src/prelude/prelude.s" "$root/src/option/option.s" \
    "$root/src/result/result.s" "$root/src/cmd/compile/internal/ast/ast.s" \
    "$work/collision.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; timeout 15 "$work/main" || status=$?
test "$status" -eq 42
echo 'production AST constructors retain their schema despite IR name collisions: PASS'
