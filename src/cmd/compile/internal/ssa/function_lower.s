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
    return function_ssa_append_block_with_edges(blocks, source_block, values, int[]())
}

func function_ssa_append_block_with_edges(function_ssa_block[] blocks, mir_program_block source_block, function_ssa_value[] values, int[] predecessors) function_ssa_block[] {
    blocks.push(function_ssa_block {
        id: source_block.id, label: "block", values: values,
        predecessors: predecessors, successors: source_block.successors, terminator: source_block.terminator,
        terminator_values: source_block.return_values,
    })
    return blocks
}

func function_ssa_append_function(function_ssa_function[] functions, mir_program_function source_function, string[] parameter_types, function_ssa_block[] blocks) function_ssa_function[] {
    exit := -1
    count := 0
    b := 0
    for b < len(blocks) {
        if blocks[b].terminator == "return" { exit = blocks[b].id; count = count + 1 }
        b = b + 1
    }
    if count != 1 { exit = -1 }
    functions.push(function_ssa_function {
        symbol: source_function.symbol, parameter_types: parameter_types,
        result_types: source_function.result_types, blocks: blocks,
        entry_block: source_function.blocks[0].id, exit_block: exit,
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
    validated := lower_mir_program_with_records(program.package_name, program.entry_symbol, program.functions, program.enums, program.records)
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
            if !mir_program_type_supported(input_function.params[p].type_name, program.records, program.enums) { return "unsupported parameter type: " + input_function.symbol }
            p = p + 1
        }
        if len(input_function.result_types) == 1 && !mir_program_type_supported(input_function.result_types[0], program.records, program.enums) {
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
        parameter_types := string[]()
        reserved := int[]()
        p := 0
        for p < len(input_function.params) {
            parameter_types = append(parameter_types, mir_program_physical_type(input_function.params[p].type_name, program.enums))
            reserved = append(reserved, input_function.params[p].value_id)
            p = p + 1
        }
        b := 0
        for b < len(input_function.blocks) {
            n := 0
            for n < len(input_function.blocks[b].instructions) {
                instruction := input_function.blocks[b].instructions[n]
                r := 0
                for r < len(instruction.result_ids) { reserved = append(reserved, instruction.result_ids[r]); r = r + 1 }
                n = n + 1
            }
            b = b + 1
        }
        next_void_id := 0
        output_blocks := function_ssa_block[]()
        b = 0
        for b < len(input_function.blocks) {
            input_block := input_function.blocks[b]
            output_values := function_ssa_value[]()
            if b == 0 {
                p = 0
                for p < len(input_function.params) {
                    parameter := input_function.params[p]
                    output_values = function_ssa_append_value(output_values, parameter.value_id, "param", int[](), input_block.id, parameter_types[p], 0, p)
                    p = p + 1
                }
            }
            n := 0
            for n < len(input_block.instructions) {
                instruction := input_block.instructions[n]
                value_id := 0
                value_type := "void"
                if len(instruction.result_ids) == 0 {
                    for function_mir_value_id_reserved(reserved, next_void_id) { next_void_id = next_void_id + 1 }
                    value_id = next_void_id
                    reserved = append(reserved, value_id)
                } else {
                    value_id = instruction.result_ids[0]
                    value_type = instruction.result_types[0]
                }
                op := instruction.op
                if op == "const_enum" { op = "const_int" }
                if op == "enum_to_int" { op = "copy" }
                value_type = mir_program_physical_type(value_type, program.enums)
                output_values = function_ssa_append_value(output_values, value_id, op, instruction.operands, input_block.id, value_type, instruction.integer_value, -1)
                output_values[len(output_values) - 1].symbol = instruction.symbol
                output_values[len(output_values) - 1].field_names = instruction.field_names
                if op == "array_new" || op == "array_get" || op == "array_len" || op == "array_append" || op == "array_set" { output_values[len(output_values) - 1].symbol = mir_program_physical_type(instruction.symbol, program.enums) }
                if op == "call" { output_calls = function_ssa_append_call(output_calls, input_function.symbol, instruction.symbol, input_block.id, value_id) }
                n = n + 1
            }
            predecessors := mir_program_predecessors(input_function, input_block.id)
            output_blocks = function_ssa_append_block_with_edges(output_blocks, input_block, output_values, predecessors)
            b = b + 1
        }
        result_types := string[]()
        r := 0
        for r < len(input_function.result_types) { result_types = append(result_types, mir_program_physical_type(input_function.result_types[r], program.enums)); r = r + 1 }
        input_function.result_types = result_types
        output_functions = function_ssa_append_function(output_functions, input_function, parameter_types, output_blocks)
        f = f + 1
    }
    records := function_ssa_record[]()
    r := 0
    for r < len(program.records) {
        source_record := program.records[r]
        types := string[]()
        f := 0
        for f < len(source_record.field_types) { types = append(types, mir_program_physical_type(source_record.field_types[f], program.enums)); f = f + 1 }
        records = append(records, function_ssa_record { symbol: source_record.symbol, field_names: source_record.field_names, field_types: types })
        r = r + 1
    }
    output_program := function_ssa_program {
        records: records, package_name: program.package_name, entry_symbol: program.entry_symbol,
        functions: output_functions, calls: output_calls,
    }
    result.error = verify_ssa_program(output_program)
    if result.error != "" { return result }
    result.program = output_program
    return result
}
