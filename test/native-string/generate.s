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
    values := function_ssa_value[]()
    values.push(function_ssa_value { id: 0, op: "const_string", type_name: "string", block_id: 0, symbol: "a\n\"\\" })
    values.push(function_ssa_value { id: 1, op: "const_string", type_name: "string", block_id: 0, symbol: "世界" })
    values.push(function_ssa_value { id: 2, op: "string_concat", type_name: "string", block_id: 0, operands: [0,1] })
    values.push(function_ssa_value { id: 3, op: "string_len", type_name: "int", block_id: 0, operands: [2] })
    values.push(function_ssa_value { id: 4, op: "const_string", type_name: "string", block_id: 0, symbol: "a\n\"\\世界" })
    values.push(function_ssa_value { id: 5, op: "string_eq", type_name: "bool", block_id: 0, operands: [2, 4] })
    values.push(function_ssa_value { id: 6, op: "bool_to_int", type_name: "int", block_id: 0, operands: [5] })
    values.push(function_ssa_value { id: 7, op: "add", type_name: "int", block_id: 0, operands: [3,6] })
    values.push(function_ssa_value { id: 8, op: "string_ne", type_name: "bool", block_id: 0, operands: [0, 1] })
    values.push(function_ssa_value { id: 9, op: "bool_to_int", type_name: "int", block_id: 0, operands: [8] })
    values.push(function_ssa_value { id: 10, op: "add", type_name: "int", block_id: 0, operands: [7,9] })
    values.push(function_ssa_value { id: 11, op: "string_lt", type_name: "bool", block_id: 0, operands: [0, 1] })
    values.push(function_ssa_value { id: 12, op: "bool_to_int", type_name: "int", block_id: 0, operands: [11] })
    values.push(function_ssa_value { id: 13, op: "add", type_name: "int", block_id: 0, operands: [10,12] })
    values.push(function_ssa_value { id: 14, op: "string_le", type_name: "bool", block_id: 0, operands: [2, 4] })
    values.push(function_ssa_value { id: 15, op: "bool_to_int", type_name: "int", block_id: 0, operands: [14] })
    values.push(function_ssa_value { id: 16, op: "add", type_name: "int", block_id: 0, operands: [13,15] })
    values.push(function_ssa_value { id: 17, op: "string_gt", type_name: "bool", block_id: 0, operands: [1, 0] })
    values.push(function_ssa_value { id: 18, op: "bool_to_int", type_name: "int", block_id: 0, operands: [17] })
    values.push(function_ssa_value { id: 19, op: "add", type_name: "int", block_id: 0, operands: [16,18] })
    values.push(function_ssa_value { id: 20, op: "string_ge", type_name: "bool", block_id: 0, operands: [2, 4] })
    values.push(function_ssa_value { id: 21, op: "bool_to_int", type_name: "int", block_id: 0, operands: [20] })
    values.push(function_ssa_value { id: 22, op: "add", type_name: "int", block_id: 0, operands: [19,21] })
    args := host_args()
    index := 0
    endpoint := 10
    if len(args) > 1 { index = -1; endpoint = -1 }
    values.push(function_ssa_value { id: 23, op: "const_int", type_name: "int", block_id: 0, integer_value: index })
    values.push(function_ssa_value { id: 24, op: "const_int", type_name: "int", block_id: 0, integer_value: 4 })
    values.push(function_ssa_value { id: 25, op: "const_int", type_name: "int", block_id: 0, integer_value: endpoint })
    values.push(function_ssa_value { id: 26, op: "string_byte_at", type_name: "int", block_id: 0, operands: [2,23] })
    values.push(function_ssa_value { id: 27, op: "string_char_at", type_name: "string", block_id: 0, operands: [2,23] })
    values.push(function_ssa_value { id: 28, op: "string_slice", type_name: "string", block_id: 0, operands: [2,24,25] })
    values.push(function_ssa_value { id: 29, op: "string_len", type_name: "int", block_id: 0, operands: [27] })
    values.push(function_ssa_value { id: 30, op: "string_len", type_name: "int", block_id: 0, operands: [28] })
    values.push(function_ssa_value { id: 31, op: "add", type_name: "int", block_id: 0, operands: [22,26] })
    values.push(function_ssa_value { id: 32, op: "add", type_name: "int", block_id: 0, operands: [31,29] })
    values.push(function_ssa_value { id: 33, op: "add", type_name: "int", block_id: 0, operands: [32,30] })
    block := function_ssa_block { id: 0, label: "entry", values: values, terminator: "return", terminator_values: [33] }
    function := function_ssa_function { symbol: "main.main", result_types: ["int"], blocks: [block], entry_block: 0, exit_block: 0 }
    program := function_ssa_program { package_name: "main", entry_symbol: "main.main", functions: [function] }
    emitted := emit_function_ssa_amd64(program)
    if emitted.error != "" { eprintln(emitted.error); return 6 }
    startup := amd64_executable_startup(program)
    if startup.error != "" { return 7 }
    assembly := emitted.assembly + startup.assembly
    println(assembly)
    return 0
}
