package compile.internal.ssa

func expect_valid(function_ssa_program p, string name) int {
    error := verify_ssa_program(p)
    if error != "" {
        eprintln("rejected valid " + name + ": " + error)
        return 1
    }
    return 0
}

func expect_invalid(function_ssa_program p, string name, string expected_error) int {
    error := verify_ssa_program(p)
    if error != expected_error {
        eprintln("wrong rejection for " + name + ": expected " + expected_error + ", got " + error)
        return 1
    }
    return 0
}

func diamond_program() function_ssa_program {
    blocks := function_ssa_block[]()
    entry := function_ssa_value[]()
    entry.push(function_ssa_value { id: 1, op: "const_bool", operands: int[](), block_id: 10, type_name: "bool" })
    blocks.push(function_ssa_block {
        id: 10, label: "entry", predecessors: int[](), successors: int[]{20, 30},
        values: entry,
        terminator: "branch", terminator_values: int[]{1},
    })
    left := function_ssa_value[]()
    left.push(function_ssa_value { id: 2, op: "const_int", operands: int[](), block_id: 20, type_name: "int" })
    blocks.push(function_ssa_block {
        id: 20, label: "left", predecessors: int[]{10}, successors: int[]{40},
        values: left,
        terminator: "jump", terminator_values: int[](),
    })
    right := function_ssa_value[]()
    right.push(function_ssa_value { id: 3, op: "const_int", operands: int[](), block_id: 30, type_name: "int" })
    blocks.push(function_ssa_block {
        id: 30, label: "right", predecessors: int[]{10}, successors: int[]{40},
        values: right,
        terminator: "jump", terminator_values: int[](),
    })
    merge := function_ssa_value[]()
    merge.push(function_ssa_value { id: 4, op: "phi", operands: int[]{2, 3}, block_id: 40, type_name: "int" })
    blocks.push(function_ssa_block {
        id: 40, label: "merge", predecessors: int[]{20, 30}, successors: int[](),
        values: merge,
        terminator: "return", terminator_values: int[]{4},
    })
    functions := function_ssa_function[]()
    functions.push(function_ssa_function {
        symbol: "sample.main", parameter_types: string[](), result_types: string[]{"int"},
        blocks: blocks, entry_block: 10, exit_block: 40,
    })
    return function_ssa_program { package_name: "sample", entry_symbol: "sample.main", functions: functions, calls: function_ssa_call[]() }
}

func loop_program() function_ssa_program {
    blocks := function_ssa_block[]()
    entry := function_ssa_value[]()
    entry.push(function_ssa_value { id: 1, op: "const_int", operands: int[](), block_id: 10, type_name: "int" })
    blocks.push(function_ssa_block {
        id: 10, label: "entry", predecessors: int[](), successors: int[]{11},
        values: entry,
        terminator: "jump", terminator_values: int[](),
    })
    header := function_ssa_value[]()
    header.push(function_ssa_value { id: 5, op: "phi", operands: int[]{1, 6}, block_id: 11, type_name: "int" })
    header.push(function_ssa_value { id: 2, op: "const_bool", operands: int[](), block_id: 11, type_name: "bool" })
    blocks.push(function_ssa_block {
        id: 11, label: "header", predecessors: int[]{10, 12}, successors: int[]{12, 13},
        values: header,
        terminator: "branch", terminator_values: int[]{2},
    })
    body := function_ssa_value[]()
    body.push(function_ssa_value { id: 6, op: "copy", operands: int[]{5}, block_id: 12, type_name: "int" })
    blocks.push(function_ssa_block {
        id: 12, label: "body", predecessors: int[]{11}, successors: int[]{11},
        values: body,
        terminator: "jump", terminator_values: int[](),
    })
    blocks.push(function_ssa_block {
        id: 13, label: "exit", predecessors: int[]{11}, successors: int[](), values: function_ssa_value[](),
        terminator: "return", terminator_values: int[]{5},
    })
    functions := function_ssa_function[]()
    functions.push(function_ssa_function {
        symbol: "sample.main", parameter_types: string[](), result_types: string[]{"int"},
        blocks: blocks, entry_block: 10, exit_block: 13,
    })
    return function_ssa_program { package_name: "sample", entry_symbol: "sample.main", calls: function_ssa_call[](), functions: functions }
}

func typed_call_program(string argument_type, string callee_type, string call_type, bool void_result, bool multiple_results) function_ssa_program {
    values := function_ssa_value[]()
    values.push(function_ssa_value { id: 0, op: "const_int", operands: int[](), block_id: 0, type_name: argument_type })
    values.push(function_ssa_value { id: 1, op: "call", operands: int[]{0}, block_id: 0, type_name: call_type })
    main_returns := int[]{1}
    main_types := string[]{call_type}
    callee_returns := int[]{0}
    callee_types := string[]{callee_type}
    if void_result {
        main_returns = int[]()
        main_types = string[]()
        callee_returns = int[]()
        callee_types = string[]()
    }
    if multiple_results {
        callee_returns = int[]{0, 0}
        callee_types = string[]{callee_type, callee_type}
    }
    blocks := function_ssa_block[]()
    blocks.push(function_ssa_block {
        id: 0, label: "entry", predecessors: int[](), successors: int[](), values: values,
        terminator: "return", terminator_values: main_returns,
    })
    functions := function_ssa_function[]()
    functions.push(function_ssa_function {
        symbol: "sample.main", parameter_types: string[](), result_types: main_types,
        blocks: blocks, entry_block: 0, exit_block: 0,
    })
    params := function_ssa_value[]()
    params.push(function_ssa_value { id: 0, op: "param", operands: int[](), block_id: 0, type_name: callee_type })
    callee_blocks := function_ssa_block[]()
    callee_blocks.push(function_ssa_block {
        id: 0, label: "entry", predecessors: int[](), successors: int[](), values: params,
        terminator: "return", terminator_values: callee_returns,
    })
    functions.push(function_ssa_function {
        symbol: "sample.identity", parameter_types: string[]{callee_type}, result_types: callee_types,
        blocks: callee_blocks, entry_block: 0, exit_block: 0,
    })
    calls := function_ssa_call[]()
    calls.push(function_ssa_call { caller: "sample.main", callee: "sample.identity", block_id: 0, value_id: 1 })
    return function_ssa_program {
        package_name: "sample", entry_symbol: "sample.main", functions: functions,
        calls: calls,
    }
}

func call_program() function_ssa_program {
    return typed_call_program("int", "int", "int", false, false)
}

func check_cfg_and_phi() int {
    failures := expect_valid(diamond_program(), "diamond with sparse block IDs and phi")
    failures = failures + expect_valid(loop_program(), "loop with backedge phi")
    p := diamond_program()
    f := p.functions[0]
    b := f.blocks[0]
    value := b.values[0]
    f = p.functions[0]
    b = f.blocks[3]
    value = b.values[0]
    value.operands = int[]{3, 2}
    b.values[0] = value
    f.blocks[3] = b
    p.functions[0] = f
    failures = failures + expect_invalid(p, "phi operands from wrong predecessor", "nondominating operand: sample.main")
    p = diamond_program()
    f = p.functions[0]
    b = f.blocks[3]
    value = b.values[0]
    value.operands = int[]{2}
    b.values[0] = value
    f.blocks[3] = b
    p.functions[0] = f
    failures = failures + expect_invalid(p, "phi argument count", "phi operand count: sample.main")
    p = diamond_program()
    f = p.functions[0]
    b = f.blocks[3]
    value = b.values[0]
    value.operands = int[]{2, 1}
    b.values[0] = value
    f.blocks[3] = b
    p.functions[0] = f
    failures = failures + expect_invalid(p, "phi operand type", "phi operand type: sample.main")
    p = diamond_program()
    f = p.functions[0]
    b = f.blocks[3]
    value = b.values[0]
    value.op = "add"
    b.values[0] = value
    f.blocks[3] = b
    p.functions[0] = f
    failures = failures + expect_invalid(p, "nonphi use of branch-local definitions", "nondominating operand: sample.main")
    p = diamond_program()
    f = p.functions[0]
    b = f.blocks[3]
    b.terminator_values = int[]{2}
    f.blocks[3] = b
    p.functions[0] = f
    failures = failures + expect_invalid(p, "nondominating return value", "nondominating operand: sample.main")
    p = diamond_program()
    f = p.functions[0]
    b = f.blocks[1]
    b.predecessors = int[]()
    f.blocks[1] = b
    p.functions[0] = f
    failures = failures + expect_invalid(p, "missing predecessor", "inconsistent successor edge: sample.main")
    p = diamond_program()
    f = p.functions[0]
    b = f.blocks[1]
    b.predecessors = int[]{10, 30}
    f.blocks[1] = b
    p.functions[0] = f
    failures = failures + expect_invalid(p, "extra predecessor", "inconsistent predecessor edge: sample.main")
    p = diamond_program()
    f = p.functions[0]
    b = f.blocks[1]
    b.predecessors = int[]{10, 10}
    f.blocks[1] = b
    p.functions[0] = f
    failures = failures + expect_invalid(p, "unbalanced duplicate edge", "inconsistent successor edge: sample.main")
    p = diamond_program()
    f = p.functions[0]
    b = f.blocks[0]
    b.successors = int[]{20, 20}
    f.blocks[0] = b
    p.functions[0] = f
    f = p.functions[0]
    b = f.blocks[1]
    b.predecessors = int[]{10, 10}
    f.blocks[1] = b
    p.functions[0] = f
    f = p.functions[0]
    b = f.blocks[2]
    b.predecessors = int[]()
    f.blocks[2] = b
    p.functions[0] = f
    f = p.functions[0]
    b = f.blocks[3]
    value = b.values[0]
    value.operands = int[]{2, 2}
    b.values[0] = value
    f.blocks[3] = b
    p.functions[0] = f
    // Both branch edges may target the same block. Remove the unreachable
    // right arm so its phi edge cannot accidentally justify a reachable use.
    f = p.functions[0]
    b = f.blocks[2]
    b.successors = int[]()
    f.blocks[2] = b
    p.functions[0] = f
    f = p.functions[0]
    b = f.blocks[2]
    b.terminator = "return"
    f.blocks[2] = b
    p.functions[0] = f
    f = p.functions[0]
    b = f.blocks[2]
    b.terminator_values = int[]{3}
    f.blocks[2] = b
    p.functions[0] = f
    f = p.functions[0]
    b = f.blocks[3]
    b.predecessors = int[]{20}
    f.blocks[3] = b
    p.functions[0] = f
    f = p.functions[0]
    b = f.blocks[3]
    value = b.values[0]
    value.operands = int[]{2}
    b.values[0] = value
    f.blocks[3] = b
    p.functions[0] = f
    failures = failures + expect_valid(p, "balanced parallel edges and unreachable block")
    p = loop_program()
    f = p.functions[0]
    b = f.blocks[1]
    value = b.values[0]
    value.operands = int[]{6, 6}
    b.values[0] = value
    f.blocks[1] = b
    p.functions[0] = f
    failures = failures + expect_invalid(p, "backedge definition used on initial phi edge", "nondominating operand: sample.main")
    return failures
}

func check_terminators() int {
    failures := 0
    p := diamond_program()
    f := p.functions[0]
    b := f.blocks[0]
    value := b.values[0]
    f = p.functions[0]
    b = f.blocks[0]
    b.terminator = ""
    f.blocks[0] = b
    p.functions[0] = f
    failures = failures + expect_invalid(p, "missing terminator", "unsupported terminator: sample.main")
    p = diamond_program()
    f = p.functions[0]
    b = f.blocks[0]
    b.terminator = "unknown"
    f.blocks[0] = b
    p.functions[0] = f
    failures = failures + expect_invalid(p, "unknown terminator", "unsupported terminator: sample.main")
    p = diamond_program()
    f = p.functions[0]
    b = f.blocks[0]
    b.terminator_values = int[]()
    f.blocks[0] = b
    p.functions[0] = f
    failures = failures + expect_invalid(p, "missing branch condition", "invalid branch: sample.main")
    p = diamond_program()
    f = p.functions[0]
    b = f.blocks[0]
    value = b.values[0]
    value.type_name = "int"
    b.values[0] = value
    f.blocks[0] = b
    p.functions[0] = f
    failures = failures + expect_invalid(p, "nonboolean branch condition", "branch condition type: sample.main")
    p = diamond_program()
    f = p.functions[0]
    condition_block := f.blocks[1]
    condition_block.values.push(function_ssa_value { id: 90, op: "const_bool", operands: int[](), block_id: 20, type_name: "bool" })
    f.blocks[1] = condition_block
    branch_block := f.blocks[0]
    branch_block.terminator_values = int[]{90}
    f.blocks[0] = branch_block
    p.functions[0] = f
    failures = failures + expect_invalid(p, "branch condition defined in successor", "nondominating operand: sample.main")
    p = diamond_program()
    f = p.functions[0]
    b = f.blocks[1]
    b.terminator_values = int[]{2}
    f.blocks[1] = b
    p.functions[0] = f
    failures = failures + expect_invalid(p, "jump with control operand", "invalid jump: sample.main")
    p = diamond_program()
    f = p.functions[0]
    b = f.blocks[1]
    b.successors = int[]()
    f.blocks[1] = b
    p.functions[0] = f
    f = p.functions[0]
    b = f.blocks[3]
    b.predecessors = int[]{30}
    f.blocks[3] = b
    p.functions[0] = f
    f = p.functions[0]
    b = f.blocks[3]
    value = b.values[0]
    value.operands = int[]{3}
    b.values[0] = value
    f.blocks[3] = b
    p.functions[0] = f
    failures = failures + expect_invalid(p, "jump without target", "invalid jump: sample.main")
    p = diamond_program()
    f = p.functions[0]
    b = f.blocks[3]
    b.terminator_values = int[]()
    f.blocks[3] = b
    p.functions[0] = f
    failures = failures + expect_invalid(p, "missing return result", "return count: sample.main")
    p = diamond_program()
    f = p.functions[0]
    b = f.blocks[3]
    b.terminator_values = int[]{4, 4}
    f.blocks[3] = b
    p.functions[0] = f
    failures = failures + expect_invalid(p, "extra return result", "return count: sample.main")
    p = diamond_program()
    f = p.functions[0]
    b = f.blocks[3]
    b.terminator_values = int[]{99}
    f.blocks[3] = b
    p.functions[0] = f
    failures = failures + expect_invalid(p, "undefined return result", "unknown terminator value: sample.main")
    return failures
}

func check_calls() int {
    failures := expect_valid(call_program(), "typed direct call")
    p := call_program()
    f := p.functions[0]
    b := f.blocks[0]
    value := b.values[0]
    call := p.calls[0]
    call = p.calls[0]
    call.value_id = 99
    p.calls[0] = call
    failures = failures + expect_invalid(p, "call edge with unknown value", "unknown call value")
    p = call_program()
    call = p.calls[0]
    call.value_id = 0
    p.calls[0] = call
    failures = failures + expect_invalid(p, "call edge attached to constant", "call edge references non-call value")
    p = call_program()
    p.calls = function_ssa_call[]()
    failures = failures + expect_invalid(p, "call instruction without edge", "missing call edge: sample.main")
    p = call_program()
    p.calls.push(function_ssa_call { caller: "sample.main", callee: "sample.main", block_id: 0, value_id: 1 })
    failures = failures + expect_invalid(p, "duplicate call edge", "duplicate call edge")
    p = call_program()
    f = p.functions[0]
    b = f.blocks[0]
    value = b.values[1]
    value.operands = int[]()
    b.values[1] = value
    f.blocks[0] = b
    p.functions[0] = f
    failures = failures + expect_invalid(p, "call argument count", "call argument count: sample.identity")
    failures = failures + expect_invalid(typed_call_program("int", "bool", "bool", false, false), "call argument type", "call argument type: sample.identity")
    failures = failures + expect_invalid(typed_call_program("int", "int", "bool", false, false), "call result type", "call result type: sample.identity")
    failures = failures + expect_invalid(typed_call_program("int", "int", "int", false, true), "unrepresentable multi-result call", "unsupported multi-result call: sample.identity")
    failures = failures + expect_valid(typed_call_program("int", "int", "void", true, false), "void direct call")
    return failures
}

func main() int {
    failures := check_cfg_and_phi() + check_terminators() + check_calls()
    if failures != 0 { return 1 }
    eprintln("P2.1 CFG, loop phi, terminator and typed-call verifier PASS")
    return 0
}
