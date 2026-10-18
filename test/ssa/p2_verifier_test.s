package compile.internal.ssa

func valid_program() function_ssa_program {
    values := function_ssa_value[]()
    values.push(function_ssa_value { id: 0, op: "const_int", operands: int[](), block_id: 0, type_name: "int" })
    blocks := function_ssa_block[]()
    blocks.push(function_ssa_block {
        id: 0, label: "entry", values: values, predecessors: int[](), successors: int[](),
        terminator: "return", terminator_values: int[]{0},
    })
    functions := function_ssa_function[]()
    functions.push(function_ssa_function {
        symbol: "sample.main", parameter_types: string[](), result_types: string[]{"int"},
        blocks: blocks, entry_block: 0, exit_block: 0,
    })
    return function_ssa_program { package_name: "sample", entry_symbol: "sample.main", functions: functions, calls: function_ssa_call[]() }
}

func check_duplicate_value() int {
    p := valid_program()
    f := p.functions[0]
    b := f.blocks[0]
    b.values.push(function_ssa_value { id: 0, op: "const_int", operands: int[](), block_id: 0, type_name: "int" })
    f.blocks[0] = b
    p.functions[0] = f
    if verify_ssa_program(p) == "" { return 1 }
    return 0
}

func check_forward_operand() int {
    p := valid_program()
    f := p.functions[0]
    b := f.blocks[0]
    b.values[0] = function_ssa_value { id: 0, op: "add", operands: int[]{1}, block_id: 0, type_name: "int" }
    b.values.push(function_ssa_value { id: 1, op: "const_int", operands: int[](), block_id: 0, type_name: "int" })
    f.blocks[0] = b
    p.functions[0] = f
    if verify_ssa_program(p) == "" { return 2 }
    return 0
}

func check_owner_block() int {
    p := valid_program()
    f := p.functions[0]
    b := f.blocks[0]
    b.values[0] = function_ssa_value { id: 0, op: "const_int", operands: int[](), block_id: 99, type_name: "int" }
    f.blocks[0] = b
    p.functions[0] = f
    if verify_ssa_program(p) == "" { return 3 }
    return 0
}

func check_return_reference() int {
    p := valid_program()
    f := p.functions[0]
    b := f.blocks[0]
    b.terminator_values = int[]{99}
    f.blocks[0] = b
    p.functions[0] = f
    if verify_ssa_program(p) == "" { return 4 }
    return 0
}

func check_return_type() int {
    p := valid_program()
    f := p.functions[0]
    f.result_types = string[]{"string"}
    p.functions[0] = f
    if verify_ssa_program(p) == "" { return 5 }
    return 0
}

func check_call_reference() int {
    p := valid_program()
    p.calls.push(function_ssa_call { caller: "sample.main", callee: "sample.main", block_id: 0, value_id: 99 })
    if verify_ssa_program(p) == "" { return 6 }
    return 0
}

func branch_program() function_ssa_program {
    blocks := function_ssa_block[]()
    condition := function_ssa_value[]()
    condition.push(function_ssa_value { id: 0, op: "const_bool", operands: int[](), block_id: 0, type_name: "bool" })
    blocks.push(function_ssa_block {
        id: 0, label: "entry", values: condition, predecessors: int[](), successors: int[]{1, 2},
        terminator: "branch", terminator_values: int[]{0},
    })
    left := function_ssa_value[]()
    left.push(function_ssa_value { id: 1, op: "const_int", operands: int[](), block_id: 1, type_name: "int" })
    blocks.push(function_ssa_block {
        id: 1, label: "then", values: left, predecessors: int[]{0}, successors: int[]{3},
        terminator: "jump", terminator_values: int[](),
    })
    blocks.push(function_ssa_block {
        id: 2, label: "else", values: function_ssa_value[](), predecessors: int[]{0}, successors: int[]{3},
        terminator: "jump", terminator_values: int[](),
    })
    blocks.push(function_ssa_block {
        id: 3, label: "merge", values: function_ssa_value[](), predecessors: int[]{1, 2}, successors: int[](),
        terminator: "return", terminator_values: int[](),
    })
    functions := function_ssa_function[]()
    functions.push(function_ssa_function {
        symbol: "sample.main", parameter_types: string[](), result_types: string[](),
        blocks: blocks, entry_block: 0, exit_block: 3,
    })
    return function_ssa_program { package_name: "sample", entry_symbol: "sample.main", functions: functions, calls: function_ssa_call[]() }
}

func check_nondominating_operand() int {
    p := branch_program()
    f := p.functions[0]
    b := f.blocks[3]
    b.values.push(function_ssa_value { id: 2, op: "copy", operands: int[]{1}, block_id: 3, type_name: "int" })
    f.blocks[3] = b
    p.functions[0] = f
    if verify_ssa_program(p) == "" { return 7 }
    return 0
}

func check_edge_symmetry() int {
    p := branch_program()
    f := p.functions[0]
    b := f.blocks[1]
    b.predecessors = int[]()
    f.blocks[1] = b
    p.functions[0] = f
    if verify_ssa_program(p) == "" { return 8 }
    return 0
}

func main() int {
    if verify_ssa_program(valid_program()) != "" { return 10 }
    if verify_ssa_program(branch_program()) != "" { return 11 }
    if check_duplicate_value() != 0 { return 1 }
    if check_forward_operand() != 0 { return 2 }
    if check_owner_block() != 0 { return 3 }
    if check_return_reference() != 0 { return 4 }
    if check_return_type() != 0 { return 5 }
    if check_call_reference() != 0 { return 6 }
    if check_nondominating_operand() != 0 { return 7 }
    if check_edge_symmetry() != 0 { return 8 }
    eprintln("P2.1 verifier: identities, definitions, CFG, dominance, calls and returns PASS")
    return 0
}
