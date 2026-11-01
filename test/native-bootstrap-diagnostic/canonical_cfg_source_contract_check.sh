#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-cfg-source-contract.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import re,sys
root,work=map(Path,sys.argv[1:])
def declaration(path,kind,name):
    source=(root/path).read_text();start=re.search(r'^'+kind+' '+name+r'\b',source,re.M).start();depth=0
    for token in re.finditer(r'"(?:\\.|[^"\\])*"|//[^\n]*|[{}]',source[start:]):
        if token[0]=='{':depth+=1
        elif token[0]=='}':
            depth-=1
            if depth==0:return source[start:start+token.end()]+'\n'
    raise RuntimeError(name)
text='package compile.internal.ir\n'
for name in ['ir_value','ir_instruction','ir_basicblock','ir_function']:
    text+=declaration('src/cmd/compile/internal/ir/middlend_ir.s','struct',name)
for name in ['ir_function_add_param','ir_function_add_block','ir_function_gen_value_id']:
    text+=declaration('src/cmd/compile/internal/ir/middlend_ir.s','func',name)
for name in ['cfg_block','control_flow_graph']:
    text+=declaration('src/cmd/compile/internal/ir/middlend_cfg.s','struct',name)
for name in ['cfg_new','cfg_zero_row','cfg_empty_rows']:
    text+=declaration('src/cmd/compile/internal/ir/middlend_cfg.s','func',name)
text+='''func main() int {
    instruction := ir_instruction { opcode: 42 }
    first := ir_basicblock { block_id: 7, instructions: [instruction] }
    last := ir_basicblock { block_id: 19, instructions: ir_instruction[]() }
    source := ir_function { name: "contract", basic_blocks: [first, last] }
    graph := cfg_new(source)
    if len(graph.blocks) != 2 { return 1 }
    if graph.blocks[0].block_id != 7 || graph.blocks[1].block_id != 19 { return 2 }
    if len(graph.blocks[0].instructions) != 1 || len(graph.blocks[1].instructions) != 0 { return 3 }
    if graph.blocks[0].instructions[0].opcode != 42 { return 4 }
    if graph.function.name != "contract" { return 5 }
    zeros := cfg_zero_row(3)
    if len(zeros) != 3 || zeros[0] != 0 || zeros[2] != 0 { return 6 }
    rows := cfg_empty_rows(2)
    if len(rows) != 2 || len(rows[0]) != 0 || len(rows[1]) != 0 { return 7 }
    rows[0] = cfg_zero_row(1)
    rows[0][0] = 42
    if rows[0][0] != 42 || len(rows[1]) != 0 { return 8 }
    mutable := ir_function { parameters: ir_value[](), basic_blocks: ir_basicblock[]() }
    parameter := ir_value { value_id: 42 }
    ir_function_add_param(mutable*, parameter)
    ir_function_add_block(mutable*, first)
    if len(mutable.parameters) != 1 || mutable.parameters[0].value_id != 42 { return 9 }
    if len(mutable.basic_blocks) != 1 || mutable.basic_blocks[0].block_id != 7 { return 10 }
    if ir_function_gen_value_id(mutable*) != 1 { return 11 }
    if ir_function_gen_value_id(mutable*) != 2 { return 12 }
    return 42
}
'''
(work/'main.s').write_text(text)
PY
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$root/src/option/option.s" "$root/src/result/result.s" "$root/src/prelude/prelude.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/main"
status=0; timeout 10 "$work/main" || status=$?
test "$status" -eq 42
echo 'CFG source contract: actual IR block fields, IDs, instruction payloads and empty blocks: PASS'
