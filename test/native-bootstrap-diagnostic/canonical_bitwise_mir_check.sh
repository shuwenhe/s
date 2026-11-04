#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-canonical-bitwise-mir.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package compile.internal
func bit_program(string op) mir_program_result {
    left := mir_program_instruction { op: "const_int", result_ids: [0], result_types: ["int"], integer_value: 40 }
    right := mir_program_instruction { op: "const_int", result_ids: [1], result_types: ["int"], integer_value: 2 }
    binary := mir_program_instruction { op: op, result_ids: [2], result_types: ["int"], operands: [0,1] }
    block := mir_program_block { id: 0, instructions: [left,right,binary], terminator: "return", return_values: [2] }
    entry := mir_program_function { symbol: "main.main", result_types: ["int"], blocks: [block] }
    return lower_mir_program("main", "main.main", [entry])
}
func validate(string op) () {
    valid := bit_program(op)
    if valid.error != "" { panic(valid.error) }
    ssa := lower_function_mir_to_ssa(valid.program)
    if ssa.error != "" { panic(ssa.error) }
    arity := bit_program(op).program
    arity.functions[0].blocks[0].instructions[2].operands = [0]
    if function_mir_input_error(arity) == "" { panic("MIR missing bit operand accepted") }
    result := bit_program(op).program
    result.functions[0].blocks[0].instructions[2].result_types = ["bool"]
    if function_mir_input_error(result) == "" { panic("MIR bool bit result accepted") }
    validate_operand(op, "bool")
    validate_operand(op, "string")
    ssa.program.functions[0].blocks[0].values[2].operands = [0]
    if verify_ssa_program(ssa.program) == "" { panic("SSA missing bit operand accepted") }
    wrong_result := lower_function_mir_to_ssa(bit_program(op).program).program
    wrong_result.functions[0].blocks[0].values[2].type_name = "bool"
    if verify_ssa_program(wrong_result) == "" { panic("SSA bool bit result accepted") }
}
func validate_operand(string op, string type_name) () {
        operand := bit_program(op).program
        operand.functions[0].blocks[0].instructions[0].op = "const_bool"
        if type_name == "string" { operand.functions[0].blocks[0].instructions[0].op = "const_string" }
        operand.functions[0].blocks[0].instructions[0].result_types[0] = type_name
        operand.functions[0].blocks[0].instructions[0].integer_value = 0
        if function_mir_input_error(operand) == "" { panic("MIR non-int bit operand accepted") }
        wrong := lower_function_mir_to_ssa(bit_program(op).program).program
        wrong.functions[0].blocks[0].values[0].op = "const_bool"
        if type_name == "string" { wrong.functions[0].blocks[0].values[0].op = "const_string" }
        wrong.functions[0].blocks[0].values[0].type_name = type_name
        wrong.functions[0].blocks[0].values[0].integer_value = 0
        if verify_ssa_program(wrong) == "" { panic("SSA non-int bit operand accepted") }
}

func main() int {
    validate("bit_and"); validate("bit_or"); validate("bit_xor"); validate("shl"); validate("shr")
    return 42
}
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$root/src/cmd/compile/internal/mir/program.s" "$root/src/cmd/compile/internal/mir/program_enum.s" "$root/src/cmd/compile/internal/ssa/program.s" "$root/src/cmd/compile/internal/ssa/function_lower.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'bitwise MIR/SSA: valid operations, malformed arity and operand/result types: PASS'
