package function_ssa_test

func instruction(string op, int id, int[] operands, int literal, string target) mir_program_instruction {
    return mir_program_instruction {
        op: op, result_ids: int[]{id}, result_types: string[]{"int"},
        operands: operands, integer_value: literal, symbol: target,
    }
}

func main_fixture() mir_program_function {
    main_params := []mir_program_parameter{}
    main_params.push(mir_program_parameter { value_id: 17, name: "x", type_name: "int" })
    main_instructions := []mir_program_instruction{}
    main_instructions.push(instruction("const_int", 0, int[]{}, -9223372036854775807 - 1, ""))
    main_instructions.push(instruction("const_int", 2, int[]{}, 9223372036854775807, ""))
    main_instructions.push(instruction("const_int", 9223372036854775807, int[]{}, -7, ""))
    main_instructions.push(instruction("copy", 5, int[]{17}, 0, ""))
    main_instructions.push(instruction("add", 8, int[]{5, 0}, 0, ""))
    main_instructions.push(instruction("sub", 9, int[]{8, 2}, 0, ""))
    main_instructions.push(instruction("mul", 10, int[]{9, 17}, 0, ""))
    main_instructions.push(instruction("div", 11, int[]{10, 2}, 0, ""))
    main_instructions.push(instruction("mod", 12, int[]{11, 2}, 0, ""))
    main_instructions.push(instruction("call", 100, int[]{17, 12}, 0, "sample.helper"))
    main_instructions.push(mir_program_instruction {
        op: "call", result_ids: int[]{}, result_types: string[]{},
        operands: int[]{100}, integer_value: 0, symbol: "sample.sink",
    })
    main_instructions.push(mir_program_instruction {
        op: "call", result_ids: int[]{}, result_types: string[]{},
        operands: int[]{100}, integer_value: 0, symbol: "sample.sink",
    })
    // ID 1 is defined after the void calls and must still be reserved.
    main_instructions.push(instruction("copy", 1, int[]{100}, 0, ""))
    main_blocks := []mir_program_block{}
    main_blocks.push(mir_program_block {
        id: 10, instructions: main_instructions, terminator: "return", return_values: int[]{1},
    })
    return mir_program_function {
        symbol: "sample.main", params: main_params, result_types: string[]{"int"},
        blocks: main_blocks, external: false,
    }
}

func helper_fixture() mir_program_function {
    helper_params := []mir_program_parameter{}
    helper_params.push(mir_program_parameter { value_id: 9223372036854775807, name: "a", type_name: "int" })
    helper_params.push(mir_program_parameter { value_id: 0, name: "b", type_name: "int" })
    helper_instructions := []mir_program_instruction{}
    helper_instructions.push(instruction("add", 200, int[]{9223372036854775807, 0}, 0, ""))
    helper_instructions.push(instruction("copy", 300, int[]{200}, 0, ""))
    helper_blocks := []mir_program_block{}
    helper_blocks.push(mir_program_block {
        id: 77, instructions: helper_instructions, terminator: "return", return_values: int[]{300},
    })
    return mir_program_function {
        symbol: "sample.helper", params: helper_params, result_types: string[]{"int"},
        blocks: helper_blocks, external: false,
    }
}

func sink_fixture() mir_program_function {
    sink_params := []mir_program_parameter{}
    sink_params.push(mir_program_parameter { value_id: 8, name: "n", type_name: "int" })
    sink_blocks := []mir_program_block{}
    sink_blocks.push(mir_program_block {
        id: 3, instructions: mir_program_instruction[]{}, terminator: "return", return_values: int[]{},
    })
    return mir_program_function {
        symbol: "sample.sink", params: sink_params, result_types: string[]{},
        blocks: sink_blocks, external: false,
    }
}

func fixture() mir_program {
    fixture_functions := []mir_program_function{}
    fixture_functions.push(main_fixture())
    fixture_functions.push(helper_fixture())
    fixture_functions.push(sink_fixture())
    unused_function := sink_fixture()
    unused_function.symbol = "sample.unused"
    fixture_functions.push(unused_function)
    fixture_result := lower_mir_program("sample", "sample.main", fixture_functions)
    return fixture_result.program
}

// These assertions fail if lowering renumbers sparse IDs, drops function/call
// order, confuses parameter positions with IDs, or loses signed literals.
func check_preservation() int {
    preserved := lower_function_mir_to_ssa(fixture())
    if preserved.error != "" { eprintln(preserved.error); return 1 }
    if preserved.program.package_name != "sample" || preserved.program.entry_symbol != "sample.main" { return 2 }
    if len(preserved.program.functions) != 4 { return 3 }
    if preserved.program.functions[0].symbol != "sample.main" || preserved.program.functions[1].symbol != "sample.helper" { return 4 }
    if preserved.program.functions[2].symbol != "sample.sink" || preserved.program.functions[3].symbol != "sample.unused" { return 5 }
    main_ssa := preserved.program.functions[0]
    if main_ssa.entry_block != 10 || main_ssa.exit_block != 10 || main_ssa.blocks[0].id != 10 { return 6 }
    if len(main_ssa.blocks) != 1 || len(main_ssa.blocks[0].values) != 14 { return 7 }
    main_values := main_ssa.blocks[0].values
    if main_values[0].op != "param" || main_values[0].id != 17 || main_values[0].parameter_index != 0 { return 8 }
    if main_values[1].id != 0 || main_values[1].integer_value != -9223372036854775807 - 1 { return 9 }
    if main_values[2].id != 2 || main_values[2].integer_value != 9223372036854775807 { return 10 }
    if main_values[3].id != 9223372036854775807 || main_values[3].integer_value != -7 { return 11 }
    if main_values[4].op != "copy" || main_values[4].operands[0] != 17 { return 12 }
    if main_values[5].op != "add" || main_values[6].op != "sub" || main_values[7].op != "mul" { return 13 }
    if main_values[8].op != "div" || main_values[9].op != "mod" { return 14 }
    if main_values[10].op != "call" || main_values[10].id != 100 || main_values[10].operands[1] != 12 { return 15 }
    if main_ssa.blocks[0].terminator != "return" || main_ssa.blocks[0].terminator_values[0] != 1 { return 16 }
    helper_ssa := preserved.program.functions[1]
    if len(helper_ssa.parameter_types) != 2 || helper_ssa.parameter_types[1] != "int" { return 17 }
    if helper_ssa.blocks[0].values[0].id != 9223372036854775807 || helper_ssa.blocks[0].values[0].parameter_index != 0 { return 18 }
    if helper_ssa.blocks[0].values[1].id != 0 || helper_ssa.blocks[0].values[1].parameter_index != 1 { return 19 }
    if helper_ssa.blocks[0].values[2].operands[0] != 9223372036854775807 || helper_ssa.blocks[0].values[3].id != 300 { return 20 }
    if len(preserved.program.calls) != 3 { return 21 }
    if preserved.program.calls[0].caller != "sample.main" || preserved.program.calls[0].callee != "sample.helper" { return 22 }
    if preserved.program.calls[0].block_id != 10 || preserved.program.calls[0].value_id != 100 { return 23 }
    if preserved.program.calls[1].callee != "sample.sink" || preserved.program.calls[1].value_id != main_values[11].id { return 24 }
    if preserved.program.calls[2].value_id != main_values[12].id { return 25 }
    if main_values[11].op != "call" || main_values[11].type_name != "void" || main_values[12].type_name != "void" { return 26 }
    if main_values[11].id < 0 || main_values[12].id < 0 || main_values[11].id == main_values[12].id { return 27 }
    sink_ssa := preserved.program.functions[2]
    if len(sink_ssa.result_types) != 0 || len(sink_ssa.blocks[0].terminator_values) != 0 { return 28 }
    if verify_ssa_program(preserved.program) != "" { return 29 }
    return 0
}

// Every fixture below mutates a once-valid MIR module. Lowering must validate
// the actual input, including call metadata, rather than trust its origin.
func check_invalid_inputs() int {
    duplicate_module := fixture()
    duplicate_main := duplicate_module.functions[0]
    duplicate_block := duplicate_main.blocks[0]
    duplicate_instruction := duplicate_block.instructions[0]
    duplicate_instruction.result_ids = int[]{17}
    duplicate_block.instructions[0] = duplicate_instruction
    duplicate_main.blocks[0] = duplicate_block
    duplicate_module.functions[0] = duplicate_main
    if lower_function_mir_to_ssa(duplicate_module).error == "" { return 1 }

    missing_module := fixture()
    missing_main := missing_module.functions[0]
    missing_block := missing_main.blocks[0]
    missing_instruction := missing_block.instructions[3]
    missing_instruction.operands = int[]{99}
    missing_block.instructions[3] = missing_instruction
    missing_main.blocks[0] = missing_block
    missing_module.functions[0] = missing_main
    if lower_function_mir_to_ssa(missing_module).error == "" { return 2 }

    edge_module := fixture()
    edge_data := edge_module.calls[0]
    edge_data.callee = "sample.sink"
    edge_module.calls[0] = edge_data
    if lower_function_mir_to_ssa(edge_module).error == "" { return 3 }

    omitted_module := fixture()
    omitted_module.calls = mir_program_call[]{}
    if lower_function_mir_to_ssa(omitted_module).error == "" { return 4 }

    extra_module := fixture()
    extra_module.calls.push(extra_module.calls[0])
    if lower_function_mir_to_ssa(extra_module).error == "" { return 5 }

    external_module := fixture()
    external_sink := external_module.functions[2]
    external_sink.external = true
    external_sink.blocks = mir_program_block[]{}
    external_module.functions[2] = external_sink
    declared_external := lower_function_mir_to_ssa(external_module)
    if declared_external.error != "" { return 6 }
    external_declaration := declared_external.program.functions[2]
    if !ssa_function_external(external_declaration) || len(external_declaration.blocks) != 0 || external_declaration.entry_block != -1 || external_declaration.exit_block != -1 { return 10 }
    external_declaration.result_types = string[]{""}
    if verify_ssa_function(external_declaration) == "" { return 11 }
    external_declaration.result_types = string[]{"int"}
    external_declaration.blocks = declared_external.program.functions[0].blocks
    if verify_ssa_function(external_declaration) == "" { return 12 }

    multi_module := fixture()
    multi_unused := multi_module.functions[3]
    multi_unused.result_types = string[]{"int", "int"}
    multi_unused_block := multi_unused.blocks[0]
    multi_unused_block.return_values = int[]{8, 8}
    multi_unused.blocks[0] = multi_unused_block
    multi_module.functions[3] = multi_unused
    if lower_function_mir_to_ssa(multi_module).error != "unsupported multi-result function: sample.unused" { return 7 }

    identity_module := fixture()
    identity_module.package_name = ""
    if lower_function_mir_to_ssa(identity_module).error == "" { return 8 }

    op_module := fixture()
    op_main := op_module.functions[0]
    op_block := op_main.blocks[0]
    op_instruction := op_block.instructions[4]
    op_instruction.op = "mystery"
    op_block.instructions[4] = op_instruction
    op_main.blocks[0] = op_block
    op_module.functions[0] = op_main
    if lower_function_mir_to_ssa(op_module).error == "" { return 9 }

    bool_module := fixture()
    bool_unused := bool_module.functions[3]
    bool_params := []mir_program_parameter{}
    bool_params.push(mir_program_parameter { value_id: 8, name: "flag", type_name: "bool" })
    bool_unused.params = bool_params
    bool_module.functions[3] = bool_unused
    if lower_function_mir_to_ssa(bool_module).error != "unsupported parameter type: sample.unused" { return 11 }
    return 0
}

func check_void_entry() int {
    void_entry := sink_fixture()
    void_entry.symbol = "sample.void_entry"
    void_entry.params = mir_program_parameter[]{}
    void_functions := []mir_program_function{}
    void_functions.push(void_entry)
    void_mir := lower_mir_program("sample", "sample.void_entry", void_functions)
    if void_mir.error != "" { return 1 }
    void_ssa := lower_function_mir_to_ssa(void_mir.program)
    if void_ssa.error != "" { return 2 }
    if len(void_ssa.program.functions[0].parameter_types) != 0 || len(void_ssa.program.functions[0].result_types) != 0 { return 3 }
    if len(void_ssa.program.functions[0].blocks[0].values) != 0 || len(void_ssa.program.functions[0].blocks[0].terminator_values) != 0 { return 4 }
    return 0
}

func main() int {
    preservation_error := check_preservation()
    if preservation_error != 0 { eprintln("MIR to SSA preservation assertion failed"); return preservation_error }
    invalid_error := check_invalid_inputs()
    if invalid_error != 0 { eprintln("MIR to SSA invalid-input assertion failed"); return 40 + invalid_error }
    void_error := check_void_entry()
    if void_error != 0 { eprintln("MIR to SSA void-entry assertion failed"); return 60 + void_error }
    eprintln("P0.1 MIR to SSA: IDs, int64 constants, params, calls, void and rejection PASS")
    return 0
}
