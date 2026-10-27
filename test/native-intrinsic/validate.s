package compile.internal
func fixture(string name, string result) mir_program_result {
    instruction := mir_program_instruction { op: "native_intrinsic", symbol: name, result_ids: [0], result_types: [result] }
    block := mir_program_block { id: 0, instructions: [instruction], terminator: "return", return_values: [0] }
    function := mir_program_function { symbol: "main.main", result_types: [result], blocks: [block] }
    return lower_mir_program("main", "main.main", [function])
}
func main() int {
    if fixture("unknown", "int").error == "" { return 1 }
    if fixture("host_args", "int").error == "" { return 2 }
    if fixture("__host_read_source", "string").error == "" { return 3 }
    valid := fixture("host_args", "string[]")
    if valid.error != "" { eprintln(valid.error); return 4 }
    lowered := lower_function_mir_to_ssa(valid.program)
    if lowered.error != "" { eprintln(lowered.error); return 5 }
    unknown := function_ssa_value { op: "native_intrinsic", symbol: "unchecked", type_name: "int" }
    if ssa_native_intrinsic_error(lowered.program.functions[0], unknown) == "" { return 6 }
    wrong := function_ssa_value { op: "native_intrinsic", symbol: "host_args", type_name: "int" }
    if ssa_native_intrinsic_error(lowered.program.functions[0], wrong) == "" { return 7 }
    metadata := function_ssa_value { op: "native_intrinsic", symbol: "host_args", type_name: "string[]", integer_value: 1 }
    if ssa_native_intrinsic_error(lowered.program.functions[0], metadata) == "" { return 8 }
    return 0
}
