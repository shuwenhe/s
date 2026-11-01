#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-canonical-enum-mir.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package compile.internal
func record_program() mir_program_result {
    record := mir_program_record { symbol: "main.Pair", field_names: ["first", "second"], field_types: ["int", "int"] }
    left := mir_program_instruction { op: "const_int", result_ids: [0], result_types: ["int"], operands: int[](), integer_value: 40 }
    right := mir_program_instruction { op: "const_int", result_ids: [1], result_types: ["int"], operands: int[](), integer_value: 2 }
    make := mir_program_instruction { op: "record_new", result_ids: [2], result_types: ["main.Pair"], operands: [0,1], symbol: "main.Pair", field_names: ["first", "second"] }
    get := mir_program_instruction { op: "record_get", result_ids: [3], result_types: ["int"], operands: [2], symbol: "main.Pair", integer_value: 0 }
    block := mir_program_block { id: 0, instructions: [left,right,make,get], terminator: "return", return_values: [3] }
    entry := mir_program_function { symbol: "main.main", result_types: ["int"], blocks: [block] }
    return lower_mir_program_with_records("main", "main.main", [entry], mir_program_enum[](), [record])
}
func array_program() mir_program_result {
    left := mir_program_instruction { op: "const_int", result_ids: [0], result_types: ["int"], operands: int[](), integer_value: 40 }
    index := mir_program_instruction { op: "const_int", result_ids: [1], result_types: ["int"], operands: int[](), integer_value: 0 }
    make := mir_program_instruction { op: "array_new", result_ids: [2], result_types: ["int[]"], operands: [0], symbol: "int[]" }
    get := mir_program_instruction { op: "array_get", result_ids: [3], result_types: ["int"], operands: [2,1], symbol: "int[]" }
    block := mir_program_block { id: 0, instructions: [left,index,make,get], terminator: "return", return_values: [3] }
    entry := mir_program_function { symbol: "main.main", result_types: ["int"], blocks: [block] }
    return lower_mir_program("main", "main.main", [entry])
}
func validate() () {
    record := record_program()
    if record.error != "" { panic(record.error) }
    ssa := lower_function_mir_to_ssa(record.program)
    if ssa.error != "" || len(ssa.program.records) != 1 { panic("valid record SSA rejected") }
    wrong_index := record_program().program
    wrong_index.functions[0].blocks[0].instructions[3].integer_value = 2
    if function_mir_input_error(wrong_index) == "" { panic("out-of-schema record field accepted") }
    wrong_type := record_program().program
    wrong_type.functions[0].blocks[0].instructions[2].result_types[0] = "main.Other"
    if function_mir_input_error(wrong_type) == "" { panic("forged record identity accepted") }
    missing := record_program().program
    missing.records = mir_program_record[]()
    if function_mir_input_error(missing) == "" { panic("missing record schema accepted") }
    duplicate := record_program().program
    duplicate.functions[0].blocks[0].instructions[2].field_names[1] = "first"
    if function_mir_input_error(duplicate) == "" { panic("duplicate MIR record initializer accepted") }
    ssa.program.functions[0].blocks[0].values[3].type_name = "bool"
    if verify_ssa_program(ssa.program) == "" { panic("forged SSA field result accepted") }
    array := array_program()
    if array.error != "" { panic(array.error) }
    array_ssa := lower_function_mir_to_ssa(array.program)
    if array_ssa.error != "" { panic(array_ssa.error) }
    wrong_array := array_program().program
    wrong_array.functions[0].blocks[0].instructions[3].symbol = "bool[]"
    if function_mir_input_error(wrong_array) == "" { panic("forged array element identity accepted") }
    array_ssa.program.functions[0].blocks[0].values[3].type_name = "bool"
    if verify_ssa_program(array_ssa.program) == "" { panic("forged SSA array result accepted") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$root/src/cmd/compile/internal/mir/program.s" "$root/src/cmd/compile/internal/mir/program_enum.s" "$root/src/cmd/compile/internal/ssa/program.s" "$root/src/cmd/compile/internal/ssa/function_lower.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'typed record and array MIR/SSA reject forged schema, identities and result types: PASS'
