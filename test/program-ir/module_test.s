package program_ir_test

func test_ids1(int a) int[] { return int[]{a} }
func test_ids2(int a, int b) int[] { return int[]{a, b} }
func test_types1(string a) string[] { return string[]{a} }

func test_functions1(mir_program_function a) mir_program_function[] {
    out := []mir_program_function{}
    out.push(a)
    return out
}
func test_functions2(mir_program_function a, mir_program_function b) mir_program_function[] {
    out := []mir_program_function{}
    out.push(a)
    out.push(b)
    return out
}
func test_functions3(mir_program_function a, mir_program_function b, mir_program_function c) mir_program_function[] {
    out := []mir_program_function{}
    out.push(a)
    out.push(b)
    out.push(c)
    return out
}

func test_instruction(string op, int id, int[] operands, int literal, string callee) mir_program_instruction {
    return mir_program_instruction {
        op: op, result_ids: test_ids1(id), result_types: test_types1("int"),
        operands: operands, integer_value: literal, symbol: callee,
    }
}

func test_add(string symbol, string op) mir_program_function {
    params := []mir_program_parameter{}
    params.push(mir_program_parameter { value_id: 0, name: "a", type_name: "int" })
    params.push(mir_program_parameter { value_id: 1, name: "b", type_name: "int" })
    values := []mir_program_instruction{}
    values.push(test_instruction(op, 2, test_ids2(0, 1), 0, ""))
    blocks := []mir_program_block{}
    blocks.push(mir_program_block {
        id: 0, instructions: values, terminator: "return", return_values: test_ids1(2),
    })
    return mir_program_function {
        symbol: symbol, params: params, result_types: test_types1("int"), blocks: blocks, external: false,
    }
}

func test_main(string callee, int second_id) mir_program_function {
    values := []mir_program_instruction{}
    values.push(test_instruction("const_int", 0, int[]{}, 3, ""))
    values.push(test_instruction("const_int", second_id, int[]{}, 4, ""))
    values.push(test_instruction("call", 2, test_ids2(0, 1), 0, callee))
    blocks := []mir_program_block{}
    blocks.push(mir_program_block {
        id: 0, instructions: values, terminator: "return", return_values: test_ids1(2),
    })
    return mir_program_function {
        symbol: "sample.main", params: mir_program_parameter[]{},
        result_types: test_types1("int"), blocks: blocks, external: false,
    }
}

func main() int {
    functions := test_functions3(test_main("sample.add", 1), test_add("sample.add", "add"), test_add("sample.unused", "sub"))
    lowered := lower_mir_program("sample", "sample.main", functions)
    if lowered.error != "" { eprintln(lowered.error); return 1 }
    if len(lowered.program.functions) != 3 { return 2 }
    if lowered.program.functions[1].symbol != "sample.add" { return 3 }
    if lowered.program.functions[1].params[0].name != "a" { return 4 }
    if lowered.program.functions[1].params[1].type_name != "int" { return 5 }
    if lowered.program.functions[1].blocks[0].instructions[0].op != "add" { return 6 }
    if lowered.program.functions[0].blocks[0].instructions[2].op != "call" { return 7 }
    if lowered.program.functions[0].blocks[0].instructions[2].operands[1] != 1 { return 8 }
    if lowered.program.functions[0].blocks[0].instructions[0].integer_value != 3 { return 9 }
    if lowered.program.functions[0].blocks[0].return_values[0] != 2 { return 10 }
    if len(lowered.program.calls) != 1 { return 11 }
    if lowered.program.calls[0].caller != "sample.main" { return 12 }
    if lowered.program.calls[0].callee != "sample.add" { return 13 }

    changed := lower_mir_program("sample", "sample.main", test_functions2(test_main("sample.add", 1), test_add("sample.add", "sub")))
    if changed.error != "" { return 14 }
    if changed.program.functions[1].blocks[0].instructions[0].op != "sub" { return 15 }

    unknown := lower_mir_program("sample", "sample.main", test_functions1(test_main("sample.missing", 1)))
    if unknown.error != "unknown callee: sample.missing" { return 16 }
    duplicate := lower_mir_program("sample", "sample.main", test_functions3(test_main("sample.add", 1), test_add("sample.add", "add"), test_add("sample.add", "sub")))
    if duplicate.error != "duplicate function: sample.add" { return 17 }
    missing_value := lower_mir_program("sample", "sample.main", test_functions2(test_main("sample.add", 9), test_add("sample.add", "add")))
    if missing_value.error != "undefined value in: sample.main" { return 18 }
    duplicate_value := lower_mir_program("sample", "sample.main", test_functions2(test_main("sample.add", 0), test_add("sample.add", "add")))
    if duplicate_value.error != "duplicate value in: sample.main" { return 19 }
    no_entry := lower_mir_program("sample", "sample.main", test_functions1(test_add("sample.add", "add")))
    if no_entry.error != "entry function not found: sample.main" { return 20 }
    unsupported := lower_mir_program("sample", "sample.add", test_functions1(test_add("sample.add", "mystery")))
    if unsupported.error != "unsupported instruction: mystery" { return 21 }
    eprintln("program IR: multi-function preservation, calls and negative cases PASS")
    return 0
}
