#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work="$root/.bootstrap/native-recursive-ast-borrow"
mkdir -p "$work"
run42() {
    S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/$1.ir" "$work/$1"
    local status=0
    "$work/$1" || status=$?
    test "$status" -eq 42
}
cat > "$work/tree.s" <<'S'
package main
struct node { int value; node[] children }
func walk(root* node) int {
    total := root.value
    for i := 0; i < len(root.children); i = i + 1 {
        child := root.children[i]
        total = total + walk(child)
    }
    return total
}
func main() int {
    leaf := node { value:21 }
    tree := node { value:21, children:[leaf] }
    return walk(tree)
}
S
"$root/bin/s_seed" --compile-native-unit "$work/tree.ir" "$work/tree.s"
run42 tree
cat > "$work/ast-main.s" <<'S'
package compile.internal.parser
func total(node* ast_node) int {
    value := node.int_data
    for i := 0; i < len(node.children); i = i + 1 {
        child := node.children[i]
        value = value + total(child)
    }
    return value
}
func main() int {
    tree := ast_new(1, 1, 1)
    ast_set_int_data(tree, 21)
    child := ast_new(48, 2, 3)
    ast_set_int_data(child, 21)
    ast_add_child(tree, child)
    ast_set_int_data(child, 99)
    return total(tree)
}
S
"$root/bin/s_seed" --compile-native-unit "$work/ast.ir" "$root/src/cmd/compile/internal/parser/frontend_ast.s" "$work/ast-main.s"
run42 ast
cat > "$work/builder-main.s" <<'S'
package compile.internal.ir
import "compile.internal.parser"
// Only the unused type-system map dependency is isolated; AST and IR are real.
struct string_ir_type_map { string[] keys; string[] values }
func check(ir_build_result result) int {
    if len(result.errors) != 0 { return 1 }
    if len(result.module.functions) != 1 { return 2 }
    function := result.module.functions[0]
    if function.name != "answer" { return 3 }
    if len(function.parameters) != 1 { return 4 }
    if function.parameters[0].var_name != "arg" { return 5 }
    if len(function.basic_blocks) != 1 { return 6 }
    block := function.basic_blocks[0]
    if block.terminator.instr_type != 306 { return 7 }
    if block.terminator.operands[0].const_value != "42" { return 8 }
    return 42
}
func main() int {
    leaf := parser.ast_node { node_type:48, string_data:"42" }
    ret := parser.ast_node { node_type:24, children:[leaf] }
    body := parser.ast_node { node_type:28, children:[ret] }
    parameter := parser.ast_node { name:"arg", type_name:"int" }
    params := parser.ast_node { node_type:28, children:[parameter] }
    return_type := parser.ast_node { node_type:60, name:"int" }
    return_types := parser.ast_node { node_type:28, children:[return_type] }
    declaration := parser.ast_node { node_type:4, name:"answer", children:[params, return_types, body] }
    tree := parser.ast_node { node_type:1, children:[declaration] }
    result := ir_builder_build(tree)
    tree.name = "changed after build"
    return check(result)
}
S
"$root/bin/s_seed" --compile-native-unit "$work/builder.ir" \
    "$root/src/cmd/compile/internal/parser/frontend_ast.s" \
    "$root/src/cmd/compile/internal/ir/middlend_ir.s" \
    "$root/src/cmd/compile/internal/ir/middlend_ir_builder.s" "$work/builder-main.s"
run42 builder
printf 'preserve artifact\n' > "$work/output"
cp "$work/output" "$work/saved"
for bad in escape copy array duplicate raw-tree multi-result; do
    case "$bad" in
        escape) body='return root'; signature='node' ;;
        copy) body='alias := root; return 0'; signature='int' ;;
        array) body='values := [root]; return 0'; signature='int' ;;
        duplicate) body='return both(root, root)'; signature='int' ;;
        raw-tree) body='return root.value'; signature='int' ;;
        multi-result) body='return root.value, root.value'; signature='(int, int)' ;;
    esac
    children='node[]'; if [ "$bad" = raw-tree ]; then children='node*[]'; fi
    cat > "$work/$bad.s" <<S
package main
struct node { int value; $children children }
func both(left* node, right* node) int { return left.value + right.value }
func invalid(root* node) $signature { $body }
func main() int { tree := node {}; return 0 }
S
    if "$root/bin/s_seed" --compile-native-unit "$work/output" "$work/$bad.s" > "$work/$bad.log" 2>&1; then
        echo "invalid recursive borrow accepted: $bad" >&2; exit 1
    fi
    grep -Eq 'unproven|unsupported_owner' "$work/$bad.log"
    cmp "$work/output" "$work/saved"
done
python3 - "$work" <<'PY'
from pathlib import Path
import sys
w=Path(sys.argv[1]); text=(w/'tree.ir').read_text()
# CALL index projection aliases an array element. Removing the LET snapshot
# must not turn that temporary into an owner, even in external IR.
line=next(l for l in text.splitlines() if l.startswith('MOV|child|'))
temp=line.split('|')[2]
(w/'call-alias.ir').write_text(text.replace(line+'\n','').replace('ARG|child|mutable_borrow|_',f'ARG|{temp}|mutable_borrow|_'))
# The independent READ operation has the same non-owning result contract.
a=text.index('ARG|root.children|_|_\nARG|i|_|_'); b=text.index(line,a)
(w/'read-alias.ir').write_text((text[:a]+f'READ|{temp}|root.children|index(i)\n'+text[b:]).replace(line+'\n','').replace('ARG|child|mutable_borrow|_',f'ARG|{temp}|mutable_borrow|_'))
(w/'merge-alias.ir').write_text(text.replace('ARG|child|mutable_borrow|_',
    'JUMP_IF_FALSE|keep_owner|1|_\nARG|root.children|_|_\nARG|i|_|_\nCALL|child|__index_get|2\nLABEL|keep_owner|_|_\nARG|child|mutable_borrow|_',1))
(w/'raw-array.ir').write_text(text.replace('RET|total|_|_', 'MOV|forged|[root]|_\nRET|total|_|_',1))
PY
cat > "$work/forbidden-tool" <<'S'
#!/bin/sh
printf called >> "$S_TEST_TOOL_LOG"
exit 99
S
chmod +x "$work/forbidden-tool"
rm -f "$work/tools.log"
for bad in call-alias read-alias merge-alias raw-array; do
    if S_SOURCE_ROOT="$root" S_TEST_TOOL_LOG="$work/tools.log" \
        S_BOOTSTRAP_AS="$work/forbidden-tool" S_BOOTSTRAP_LD="$work/forbidden-tool" \
        "$root/bin/s_seed" --emit-standalone-amd64 "$work/$bad.ir" "$work/output" > "$work/$bad.log" 2>&1; then
        echo "forged recursive borrow accepted: $bad" >&2; exit 1
    fi
    grep -q unproven "$work/$bad.log"
    cmp "$work/output" "$work/saved"
    test ! -e "$work/tools.log"
done
# Fully qualified constants keep their initializer's declaration package.
cat > "$work/constants.s" <<'S'
package alpha
const base = 1
const answer = base
S
cat > "$work/constants-main.s" <<'S'
package main
import "alpha"
func main() int { base := 41; return alpha.answer + base }
S
"$root/bin/s_seed" --compile-native-unit "$work/constants.ir" "$work/constants.s" "$work/constants-main.s"
run42 constants
cat > "$work/constant-shadow.s" <<'S'
package main
import "alpha"
struct cell { int answer }
func read(cell alpha) int { return alpha.answer }
func main() int {
    alpha := cell { answer:42 }
    return read(alpha)
}
S
"$root/bin/s_seed" --compile-native-unit "$work/constant-shadow.ir" "$work/constants.s" "$work/constant-shadow.s"
run42 constant-shadow
echo 'owned recursive AST snapshots, real builder, reborrows and escape/alias rejection: PASS'
