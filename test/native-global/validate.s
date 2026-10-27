package compile.internal
func function(string symbol, string result, mir_program_instruction[] instructions, int returned) mir_program_function {
    block := mir_program_block { id: 0, instructions: instructions, terminator: "return", return_values: [returned] }
    return mir_program_function { symbol: symbol, result_types: [result], blocks: [block] }
}
func fixture(string mode) mir_program_result {
    first := mir_program_instruction { op: "const_int", result_ids: [0], result_types: ["int"], integer_value: 40 }
    if mode == "cycle" { first = mir_program_instruction { op: "global_get", result_ids: [0], result_types: ["int"], symbol: "main.B" } }
    init_a := function("main.init_a", "int", [first], 0)
    if mode == "initializer_args" {
        parameter := mir_program_parameter { value_id: 9, name: "argument", type_name: "int" }
        init_a.params = [parameter];
    }
    load := mir_program_instruction { op: "global_get", result_ids: [0], result_types: ["int"], symbol: "main.A" }
    helper := function("main.helper", "int", [load], 0)
    call := mir_program_instruction { op: "call", result_ids: [0], result_types: ["int"], symbol: "main.helper" }
    two := mir_program_instruction { op: "const_int", result_ids: [1], result_types: ["int"], integer_value: 2 }
    add := mir_program_instruction { op: "add", result_ids: [2], result_types: ["int"], operands: [0,1] }
    init_b := function("main.init_b", "int", [call,two,add], 2)
    global_name := "main.B"
    result_type := "int"
    if mode == "unknown" { global_name = "missing" }
    if mode == "load_type" { result_type = "bool" }
    read := mir_program_instruction { op: "global_get", result_ids: [0], result_types: [result_type], symbol: global_name }
    if mode == "operand_type" { read = mir_program_instruction { op: "const_bool", result_ids: [0], result_types: ["bool"], integer_value: 1 } }
    store := mir_program_instruction { op: "global_set", result_ids: [1], result_types: ["()"], operands: [0], symbol: "main.A" }
    if mode == "metadata" { store.integer_value = 1 }
    if mode == "store_type" { store.result_types = ["int"] }
    main := function("main.main", "int", [read,store], 0)
    initializer := "main.init_a"
    if mode == "initializer" { initializer = "missing" }
    type_name := "int"
    if mode == "initializer_type" { type_name = "string" }
    if mode == "unsupported_type" { type_name = "float" }
    a := mir_program_global { symbol: "main.A", type_name: type_name, initializer: initializer }
    b := mir_program_global { symbol: "main.B", type_name: "int", initializer: "main.init_b" }
    if mode == "duplicate" { a.symbol = "main.B" }
    return lower_mir_program_with_globals("main", "main.main", [main,init_b,helper,init_a], mir_program_enum[](), mir_program_record[](), [b,a])
}
func main() int {
    modes := ["unknown", "load_type", "metadata", "store_type", "initializer", "initializer_type", "duplicate", "cycle", "initializer_args", "operand_type", "unsupported_type"];
    i := 0
    for i < len(modes) {
        if fixture(modes[i]).error == "" { eprintln(modes[i]); return 1 }
        i = i + 1
    }
    valid := fixture("")
    if valid.error != "" { eprintln(valid.error); return 2 }
    order := mir_program_global_order(valid.program.globals, valid.program.functions)
    if order.error != "" || len(order.order) != 2 || order.order[0] != 1 { return 3 }
    lowered := lower_function_mir_to_ssa(valid.program)
    if lowered.error != "" { eprintln(lowered.error); return 4 }
    if len(lowered.program.globals) != 2 { return 5 }
    wrong := function_ssa_value { op: "global_get", type_name: "bool", symbol: "main.A" }
    if ssa_global_value_error(lowered.program.functions[0], wrong, lowered.program.globals) == "" { return 6 }
    unknown := function_ssa_value { op: "global_set", type_name: "()", operands: [0], symbol: "missing" }
    if ssa_global_value_error(lowered.program.functions[0], unknown, lowered.program.globals) == "" { return 7 }
    cycle_value := function_ssa_value { id: 0, op: "global_get", type_name: "int", symbol: "main.self", block_id: 0 }
    cycle_block := function_ssa_block { id: 0, label: "entry", values: [cycle_value], terminator: "return", terminator_values: [0] }
    cycle_function := function_ssa_function { symbol: "main.self_init", result_types: ["int"], blocks: [cycle_block], entry_block: 0, exit_block: 0 }
    cycle_global := function_ssa_global { symbol: "main.self", type_name: "int", initializer: "main.self_init" }
    cycle_program := function_ssa_program { package_name: "main", entry_symbol: "main.self_init", functions: [cycle_function], globals: [cycle_global] }
    if verify_ssa_program(cycle_program) == "" { return 8 }
    return 0
}
