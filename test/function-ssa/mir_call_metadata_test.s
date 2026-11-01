package function_ssa_mir_calls_test

func empty_function(string symbol) mir_program_function {
    empty_blocks := []mir_program_block{}
    empty_blocks.push(mir_program_block {
        id: 7, instructions: mir_program_instruction[]{}, terminator: "return", return_values: int[]{},
    })
    return mir_program_function {
        symbol: symbol, params: mir_program_parameter[]{}, result_types: string[]{},
        blocks: empty_blocks, external: false,
    }
}

func main() int {
    caller_instructions := []mir_program_instruction{}
    caller_instructions.push(mir_program_instruction {
        op: "call", result_ids: int[]{}, result_types: string[]{}, operands: int[]{}, integer_value: 0, symbol: "sample.first",
    })
    caller_instructions.push(mir_program_instruction {
        op: "call", result_ids: int[]{}, result_types: string[]{}, operands: int[]{}, integer_value: 0, symbol: "sample.second",
    })
    caller_blocks := []mir_program_block{}
    caller_blocks.push(mir_program_block {
        id: 99, instructions: caller_instructions, terminator: "return", return_values: int[]{},
    })
    caller_function := mir_program_function {
        symbol: "sample.main", params: mir_program_parameter[]{}, result_types: string[]{},
        blocks: caller_blocks, external: false,
    }
    call_functions := []mir_program_function{}
    call_functions.push(caller_function)
    call_functions.push(empty_function("sample.first"))
    call_functions.push(empty_function("sample.second"))
    call_module := lower_mir_program("sample", "sample.main", call_functions)
    if call_module.error != "" { return 1 }
    if len(call_module.program.calls) != 2 { return 2 }
    if call_module.program.calls[0].callee != "sample.first" || call_module.program.calls[0].instruction_index != 0 {
        eprintln("MIR call metadata lost first call identity")
        return 3
    }
    if call_module.program.calls[1].callee != "sample.second" || call_module.program.calls[1].instruction_index != 1 { return 4 }
    eprintln("MIR call metadata: distinct direct call edges PASS")
    return 0
}
