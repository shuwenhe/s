package compile.internal
func fixture(string result, int[] size_operands) mir_program_result {
    first := mir_program_instruction { op: "const_string", result_ids: [0], result_types: ["string"], symbol: "a\n\"\\" }
    second := mir_program_instruction { op: "const_string", result_ids: [1], result_types: ["string"], symbol: "世界" }
    combined := mir_program_instruction { op: "string_concat", result_ids: [2], result_types: [result], operands: [0,1] }
    size := mir_program_instruction { op: "string_len", result_ids: [3], result_types: ["int"], operands: size_operands }
    block := mir_program_block { id: 0, instructions: [first,second,combined,size], terminator: "return", return_values: [3] }
    function := mir_program_function { symbol: "main.main", result_types: ["int"], blocks: [block] }
    return lower_mir_program("main", "main.main", [function])
}
func main() int {
    if fixture("int", [2]).error == "" { return 2 }
    if fixture("string", [0,1]).error == "" { return 3 }
    valid := fixture("string", [2])
    if valid.error != "" { eprintln(valid.error); return 1 }
    lowered := lower_function_mir_to_ssa(valid.program)
    if lowered.error != "" { eprintln(lowered.error); return 4 }
    bad_value := function_ssa_value { op: "string_concat", type_name: "string", operands: [0,3] }
    if ssa_string_value_error(lowered.program.functions[0], bad_value) == "" { return 5 }
    comparison := function_ssa_value { op: "string_eq", type_name: "int", operands: [0,1] }
    if ssa_string_value_error(lowered.program.functions[0], comparison) == "" { return 8 }
    malformed := function_ssa_value { op: "const_string", type_name: "string", operands: [0] }
    if ssa_string_value_error(lowered.program.functions[0], malformed) == "" { return 9 }
    metadata := function_ssa_value { op: "const_string", type_name: "string", integer_value: 1 }
    if ssa_string_value_error(lowered.program.functions[0], metadata) == "" { return 10 }
    wrong_index := function_ssa_value { op: "string_slice", type_name: "string", operands: [0,1,3] }
    if ssa_string_value_error(lowered.program.functions[0], wrong_index) == "" { return 11 }
    wrong_target := function_ssa_value { op: "string_byte_at", type_name: "int", operands: [3,3] }
    if ssa_string_value_error(lowered.program.functions[0], wrong_target) == "" { return 12 }
    return 0
}
