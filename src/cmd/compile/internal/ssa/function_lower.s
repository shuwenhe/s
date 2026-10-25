package compile.internal


struct function_ssa_result {
    function_ssa_program program
    string error
}

// Returning the array snapshots its records on hosted executors whose local
// struct-literal and function-result storage is reused by loop iterations.
func function_ssa_append_value(function_ssa_value[] values, int id, string op, int[] operands, int block_id, string type_name, int integer_value, int parameter_index) function_ssa_value[] {
    values.push(function_ssa_value {
        id: id, op: op, operands: operands, block_id: block_id, type_name: type_name,
        integer_value: integer_value, parameter_index: parameter_index,
    })
    return values
}

func function_ssa_append_call(function_ssa_call[] calls, string caller, string callee, int block_id, int value_id) function_ssa_call[] {
    calls.push(function_ssa_call { caller: caller, callee: callee, block_id: block_id, value_id: value_id })
    return calls
}

func function_ssa_append_block(function_ssa_block[] blocks, mir_program_block source_block, function_ssa_value[] values) function_ssa_block[] {
    blocks.push(function_ssa_block {
        id: source_block.id, label: "entry", values: values,
        predecessors: int[]{}, successors: int[]{}, terminator: source_block.terminator,
        terminator_values: source_block.return_values,
    })
    return blocks
}

func function_ssa_append_function(function_ssa_function[] functions, mir_program_function source_function, string[] parameter_types, function_ssa_block[] blocks) function_ssa_function[] {
    functions.push(function_ssa_function {
        symbol: source_function.symbol, parameter_types: parameter_types,
        result_types: source_function.result_types, blocks: blocks,
        entry_block: source_function.blocks[0].id, exit_block: source_function.blocks[0].id,
    })
    return functions
}

func function_mir_value_id_reserved(int[] reserved, int id) bool {
    i := 0
    for i < len(reserved) {
        if reserved[i] == id { return true }
        i = i + 1
    }
    return false
}

// Re-run MIR validation on the supplied functions. The caller can mutate a
// previously lowered module, so its saved call metadata is checked as well.
func function_mir_input_error(mir_program program) string {
    if program.package_name == "" || program.entry_symbol == "" { return "invalid program identity" }
    validated := lower_mir_program(program.package_name, program.entry_symbol, program.functions)
    if validated.error != "" { return validated.error }
    if len(program.calls) != len(validated.program.calls) { return "MIR: call edge count" }
    i := 0
    for i < len(program.calls) {
        supplied := program.calls[i]
        actual := validated.program.calls[i]
        if supplied.caller != actual.caller || supplied.callee != actual.callee || supplied.block_id != actual.block_id || supplied.instruction_index != actual.instruction_index {
            return "MIR call edge mismatch"
        }
        i = i + 1
    }
    i = 0
    for i < len(program.functions) {
        input_function := program.functions[i]
        if input_function.external { return "unsupported external function: " + input_function.symbol }
        if len(input_function.result_types) > 1 { return "unsupported multi-result function: " + input_function.symbol }
        p := 0
        for p < len(input_function.params) {
            if input_function.params[p].type_name != "int" && input_function.params[p].type_name != "()" { return "unsupported parameter type: " + input_function.symbol }
            p = p + 1
        }
        if len(input_function.result_types) == 1 && input_function.result_types[0] != "int" && input_function.result_types[0] != "()" {
            return "unsupported result type: " + input_function.symbol
        }
        i = i + 1
    }
    return ""
}

// The P0 slice has one straight-line block per function. Preserve MIR value
// identities and block IDs; ABI layout and instruction selection follow later.
func lower_function_mir_to_ssa(mir_program program) function_ssa_result {
    empty_program := function_ssa_program {
        package_name: program.package_name, entry_symbol: program.entry_symbol,
        functions: function_ssa_function[]{}, calls: function_ssa_call[]{},
    }
    result := function_ssa_result { program: empty_program, error: function_mir_input_error(program) }
    if result.error != "" { return result }
    output_functions := []function_ssa_function{}
    output_calls := []function_ssa_call{}
    f := 0
    for f < len(program.functions) {
        input_function := program.functions[f]
        input_block := input_function.blocks[0]
        output_values := []function_ssa_value{}
        parameter_types := string[]{}
        reserved := int[]{}
        p := 0
        for p < len(input_function.params) {
            input_parameter := input_function.params[p]
            parameter_types.push(input_parameter.type_name)
            reserved.push(input_parameter.value_id)
            output_values = function_ssa_append_value(output_values, input_parameter.value_id, "param", int[]{}, input_block.id, input_parameter.type_name, 0, p)
            p = p + 1
        }
        // Reserve every original result before allocating void-call values.
        // Searching for a free gap also handles a sparse INT64_MAX value ID.
        n := 0
        for n < len(input_block.instructions) {
            reservation_instruction := input_block.instructions[n]
            r := 0
            for r < len(reservation_instruction.result_ids) {
                reserved.push(reservation_instruction.result_ids[r])
                r = r + 1
            }
            n = n + 1
        }
        next_void_id := 0
        n = 0
        for n < len(input_block.instructions) {
            input_instruction := input_block.instructions[n]
            value_id := 0
            value_type := "void"
            if len(input_instruction.result_ids) == 0 {
                for function_mir_value_id_reserved(reserved, next_void_id) { next_void_id = next_void_id + 1 }
                value_id = next_void_id
                reserved.push(value_id)
            } else {
                value_id = input_instruction.result_ids[0]
                value_type = input_instruction.result_types[0]
            }
            output_values = function_ssa_append_value(output_values, value_id, input_instruction.op, input_instruction.operands, input_block.id, value_type, input_instruction.integer_value, -1)
            if input_instruction.op == "call" {
                output_calls = function_ssa_append_call(output_calls, input_function.symbol, input_instruction.symbol, input_block.id, value_id)
            }
            n = n + 1
        }
        output_blocks := []function_ssa_block{}
        output_blocks = function_ssa_append_block(output_blocks, input_block, output_values)
        output_functions = function_ssa_append_function(output_functions, input_function, parameter_types, output_blocks)
        f = f + 1
    }
    output_program := function_ssa_program {
        package_name: program.package_name, entry_symbol: program.entry_symbol,
        functions: output_functions, calls: output_calls,
    }
    result.error = verify_ssa_program(output_program)
    if result.error != "" { return result }
    result.program = output_program
    return result
}
