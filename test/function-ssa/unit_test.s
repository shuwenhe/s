package unit_boundary_test
func fixture(string op, string type_name, int literal, int[] operands) function_ssa_function {
    values := function_ssa_value[]()
    values.push(function_ssa_value { id: 0, op: "const_int", operands: int[]{}, block_id: 0, type_name: "int", integer_value: 0, parameter_index: 0 })
    values.push(function_ssa_value { id: 1, op: op, operands: operands, block_id: 0, type_name: type_name, integer_value: literal, parameter_index: 0 })
    block := function_ssa_block { id: 0, label: "entry", values: values, predecessors: int[]{}, successors: int[]{}, terminator: "return", terminator_values: int[]{1} }
    blocks := function_ssa_block[]()
    blocks.push(block)
    return function_ssa_function {
        symbol: "unit", parameter_types: string[]{}, result_types: string[]{"()"}, entry_block: 0, exit_block: 0,
        blocks: blocks,
    }
}
func main() int {
    if verify_ssa_function(fixture("const_unit", "()", 0, int[]{})) != "" { return 1 }
    if verify_ssa_function(fixture("const_unit", "int", 0, int[]{})) == "" { return 2 }
    if verify_ssa_function(fixture("const_unit", "()", 1, int[]{})) == "" { return 3 }
    if verify_ssa_function(fixture("const_unit", "()", 0, int[]{0})) == "" { return 4 }
    if verify_ssa_function(fixture("const_int", "()", 0, int[]{})) == "" { return 5 }
    if verify_ssa_function(fixture("copy", "()", 0, int[]{0})) == "" { return 6 }
    return 0
}
