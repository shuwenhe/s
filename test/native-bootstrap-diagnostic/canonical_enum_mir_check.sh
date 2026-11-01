#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-canonical-enum-mir.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package compile.internal
func validate() () {
    enumeration := mir_program_enum { symbol: "main.Code", variants: ["answer"], tags: [40] }
    other := mir_program_enum { symbol: "main.Other", variants: ["answer"], tags: [40] }
    parameter := mir_program_parameter { value_id: 0, name: "code", type_name: "main.Code" }
    convert := mir_program_instruction { op: "enum_to_int", result_ids: [1], result_types: ["int"], operands: [0], integer_value: 0, symbol: "" }
    score_block := mir_program_block { id: 0, instructions: [convert], terminator: "return", return_values: [1] }
    score := mir_program_function { symbol: "main.score", params: [parameter], result_types: ["int"], blocks: [score_block], external: false }
    constant := mir_program_instruction { op: "const_enum", result_ids: [0], result_types: ["main.Code"], operands: int[](), integer_value: 40, symbol: "main.Code.answer" }
    call := mir_program_instruction { op: "call", result_ids: [1], result_types: ["int"], operands: [0], integer_value: 0, symbol: "main.score" }
    block := mir_program_block { id: 0, instructions: [constant, call], terminator: "return", return_values: [1] }
    entry := mir_program_function { symbol: "main.main", params: mir_program_parameter[](), result_types: ["int"], blocks: [block], external: false }
    lowered := lower_mir_program_with_enums("main", "main.main", [score, entry], [enumeration, other])
    if lowered.error != "" || len(lowered.program.enums) != 2 { panic("valid enum MIR rejected") }
    ssa := lower_function_mir_to_ssa(lowered.program)
    if ssa.error != "" || ssa.program.functions[0].parameter_types[0] != "int" || ssa.program.functions[0].blocks[0].values[1].op != "copy" { panic("enum representation lowering failed") }
    bad_tag := lowered.program
    bad_tag.functions[1].blocks[0].instructions[0].integer_value = 41
    if function_mir_input_error(bad_tag) == "" { panic("forged tag accepted") }
    bad_type := lowered.program
    bad_type.functions[1].blocks[0].instructions[0].result_types[0] = "main.Other"
    bad_type.functions[1].blocks[0].instructions[0].symbol = "main.Other.answer"
    if function_mir_input_error(bad_type) == "" { panic("different enum argument accepted") }
    undeclared := lowered.program
    undeclared.enums = mir_program_enum[]()
    if function_mir_input_error(undeclared) == "" { panic("undeclared enum accepted") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$root/src/cmd/compile/internal/mir/program.s" "$root/src/cmd/compile/internal/mir/program_enum.s" "$root/src/cmd/compile/internal/ssa/program.s" "$root/src/cmd/compile/internal/ssa/function_lower.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'typed enum MIR validates declaration/tag/call identity before SSA representation lowering: PASS'
