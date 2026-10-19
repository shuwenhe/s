#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-ssa-lower-binding.XXXXXX)
source_file="$root/src/cmd/compile/internal/core/ssa_lower.s"
"$root/bin/s_seed" --dump-ast "$source_file" "$work/ssa.ast"
rg -q 'FN_STMT .* name=make_ssa_to_machine params=2$' "$work/ssa.ast"
rg -q 'param=ctx type=codegen_context\*$' "$work/ssa.ast"
rg -q 'param=function_data type=ssa_function\*$' "$work/ssa.ast"
rg -q 'param=b type=ssa_block\*$' "$work/ssa.ast"
rg -q 'param=m type=ssa_to_machine\*$' "$work/ssa.ast"
rg -q 'LET_STMT .* name=tm ' "$work/ssa.ast"
rg -q 'STRUCT_EXPR .* type=ssa_to_machine fields=3$' "$work/ssa.ast"
for field in ctx function_data progs; do rg -q "field=$field$" "$work/ssa.ast"; done
if rg -n '\btm\.|\.func\b' "$source_file"; then
    echo 'stale constructor-local or keyword field reference remains' >&2
    exit 1
fi
printf 'SSA lowering bindings and parameter AST: PASS; AST=%s\n' "$work/ssa.ast"
