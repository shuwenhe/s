#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-core-constructors.XXXXXX)
check() {
    local file=$1 binding=$2 type=$3 fields=$4
    "$root/bin/s_seed" --dump-ast "$root/src/cmd/compile/internal/core/$file.s" "$work/$file.ast"
    rg -q "LET_STMT .* name=$binding " "$work/$file.ast"
    rg -q "STRUCT_EXPR .* type=$type fields=$fields$" "$work/$file.ast"
    printf '%s constructor AST: PASS\n' "$file"
}
check codegen_x86_64 builder machine_code_builder 5
check compilation_driver driver native_compilation_driver 4
check compiler_pipeline pipeline compiler_pipeline 2
check direct_codegen gen direct_code_generator 4
check end_to_end compiler end_to_end_compiler 5
check instruction_selector selector instruction_selector 3
check instr_select is instr_selector 1
check linker lnk linker 3
check live_range state reg_alloc_state 4
check native_compiler compiler native_compiler 6
check optimizer opt optimizer 2
check elf64_gen writer elf64_writer 4
rg -q 'STRUCT_EXPR .* type=elf64_section fields=12$' "$work/elf64_gen.ast"
# Execute the production machine builder constructor separately from its
# methods. The canonical gate still compiles the full production closure.
sed '/^func (machine_code_builder\* b) emit_byte/,$d' \
    "$root/src/cmd/compile/internal/core/codegen_x86_64.s" > "$work/values.s"
printf '%s\n' \
    'func main() int {' \
    ' b := new_machine_code_builder()' \
    ' if len(b.instructions) != 0 { return 1 }' \
    ' if len(b.machine_code) != 0 { return 2 }' \
    ' if len(b.labels) != 0 { return 3 }' \
    ' if len(b.functions) != 0 { return 4 }' \
    ' if b.next_reg != 0 { return 5 }' \
    ' return 0' \
    '}' >> "$work/values.s"
"$root/bin/s_seed" "$work/values.s" "$work/values.ir"
"$root/bin/s_seed" --emit-bin "$work/values.ir" "$work/values"
"$work/values"
printf 'machine builder initial values: PASS; artifacts=%s\n' "$work"
