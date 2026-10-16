package mir_c_codegen_test

// This fixture calls the existing module MIR verifier/producer. No source
// scanner or AST interpreter participates in the code-generation test.
func cg_ins(string op, int id, int[] args, int literal, string symbol) mir_program_instruction {
    return mir_program_instruction {
        op: op, result_ids: int[]{id}, result_types: string[]{"int"},
        operands: args, integer_value: literal, symbol: symbol,
    }
}

func cg_function(string symbol, mir_program_parameter[] params, mir_program_instruction[] instructions, int returned) mir_program_function {
    blocks := []mir_program_block{}
    blocks.push(mir_program_block { id: 0, instructions: instructions, terminator: "return", return_values: int[]{returned} })
    return mir_program_function { symbol: symbol, params: params, result_types: string[]{"int"}, blocks: blocks, external: false }
}

func cg_fixture(string mode) mir_program_result {
    params := []mir_program_parameter{}
    params.push(mir_program_parameter { value_id: 0, name: "input", type_name: "int" })
    values := []mir_program_instruction{}
    values.push(cg_ins("const_int", 1, int[]{}, 3, ""))
    values.push(cg_ins("call", 2, int[]{0, 1}, 0, "sample.multiply"))
    literal := 4
    if mode == "changed" { literal = 9 }
    if mode == "min" { literal = -9223372036854775807 - 1 }
    values.push(cg_ins("const_int", 3, int[]{}, literal, ""))
    op := "add"
    if mode == "subtract" { op = "sub" }
    if mode == "invalid_op" { op = "unimplemented" }
    values.push(cg_ins(op, 4, int[]{2, 3}, 0, ""))
    if mode == "undefined" { values.push(cg_ins("copy", 5, int[]{999}, 0, "")) }
    functions := []mir_program_function{}
    functions.push(cg_function("sample.main", params, values, 4))
    helper_params := []mir_program_parameter{}
    helper_params.push(mir_program_parameter { value_id: 0, name: "a", type_name: "int" })
    helper_params.push(mir_program_parameter { value_id: 1, name: "b", type_name: "int" })
    helper_values := []mir_program_instruction{}
    helper_values.push(cg_ins("mul", 2, int[]{0, 1}, 0, ""))
    functions.push(cg_function("sample.multiply", helper_params, helper_values, 2))
    // Keep an uncalled function to test whole-module emission and C naming.
    unused := []mir_program_instruction{}
    unused.push(cg_ins("const_int", 8, int[]{}, -7, ""))
    functions.push(cg_function("other.main", mir_program_parameter[]{}, unused, 8))
    if mode == "external" {
        functions[1].external = true
        functions[1].blocks = mir_program_block[]()
    }
    if mode == "bad_type" {
        functions[2].result_types = string[]{"string"}
        functions[2].blocks[0].instructions[0].result_types = string[]{"string"}
        functions[2].blocks[0].instructions[0].op = "copy"
        functions[2].params = params
        functions[2].params[0].type_name = "string"
        functions[2].blocks[0].instructions[0].operands = int[]{0}
    }
    return lower_mir_program("sample", "sample.main", functions)
}

func main() int {
    args := host_args()
    mode := "base"
    if len(args) > 1 { mode = args[1] }
    lowered := cg_fixture(mode)
    if lowered.error != "" { eprintln(lowered.error); return 1 }
    emitted := emit_mir_program_c(lowered.program)
    if emitted.error != "" {
        if emitted.code != "" { eprintln("failed emission leaked partial C"); return 2 }
        eprintln(emitted.error)
        return 1
    }
    println(emitted.code)
    return 0
}
