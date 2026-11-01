package compile.internal
func function(string symbol, string result, function_ssa_value[] values, int returned) function_ssa_function {
    block := function_ssa_block { id: 0, label: "entry", values: values, terminator: "return", terminator_values: [returned] }
    return function_ssa_function { symbol: symbol, result_types: [result], blocks: [block], entry_block: 0, exit_block: 0 }
}
func main() int {
    functions := function_ssa_function[]()
    values := function_ssa_value[]()
    values.push(function_ssa_value { id: 0, op: "const_int", type_name: "int", integer_value: 40, block_id: 0 })
    functions.push(function("main.init_a", "int", values, 0))
    values = function_ssa_value[]()
    values.push(function_ssa_value { id: 0, op: "global_get", type_name: "int", symbol: "main.A", block_id: 0 })
    functions.push(function("main.helper", "int", values, 0))
    values = function_ssa_value[]()
    values.push(function_ssa_value { id: 0, op: "call", type_name: "int", block_id: 0 })
    values.push(function_ssa_value { id: 1, op: "const_int", type_name: "int", integer_value: 2, block_id: 0 })
    values.push(function_ssa_value { id: 2, op: "add", type_name: "int", operands: [0,1], block_id: 0 })
    functions.push(function("main.init_b", "int", values, 2))
    values = function_ssa_value[]()
    values.push(function_ssa_value { id: 0, op: "const_string", type_name: "string", symbol: "hi", block_id: 0 })
    functions.push(function("main.init_text", "string", values, 0))
    values = function_ssa_value[]()
    values.push(function_ssa_value { id: 0, op: "global_get", type_name: "int", symbol: "main.A", block_id: 0 })
    values.push(function_ssa_value { id: 1, op: "const_int", type_name: "int", integer_value: 1, block_id: 0 })
    values.push(function_ssa_value { id: 2, op: "add", type_name: "int", operands: [0,1], block_id: 0 })
    values.push(function_ssa_value { id: 3, op: "global_set", type_name: "()", operands: [2], symbol: "main.A", block_id: 0 })
    values.push(function_ssa_value { id: 4, op: "global_get", type_name: "int", symbol: "main.B", block_id: 0 })
    values.push(function_ssa_value { id: 5, op: "add", type_name: "int", operands: [2,4], block_id: 0 })
    values.push(function_ssa_value { id: 6, op: "global_get", type_name: "string", symbol: "main.text", block_id: 0 })
    values.push(function_ssa_value { id: 7, op: "string_len", type_name: "int", operands: [6], block_id: 0 })
    values.push(function_ssa_value { id: 8, op: "add", type_name: "int", operands: [5,7], block_id: 0 })
    values.push(function_ssa_value { id: 9, op: "global_get", type_name: "int", symbol: "main.zero", block_id: 0 })
    values.push(function_ssa_value { id: 10, op: "add", type_name: "int", operands: [8,9], block_id: 0 })
    functions.push(function("main.main", "int", values, 10))
    globals := function_ssa_global[]()
    globals.push(function_ssa_global { symbol: "main.B", type_name: "int", initializer: "main.init_b" })
    globals.push(function_ssa_global { symbol: "main.A", type_name: "int", initializer: "main.init_a" })
    globals.push(function_ssa_global { symbol: "main.text", type_name: "string", initializer: "main.init_text" })
    globals.push(function_ssa_global { symbol: "main.zero", type_name: "int" })
    edge := function_ssa_call { caller: "main.init_b", callee: "main.helper", block_id: 0, value_id: 0 }
    program := function_ssa_program { package_name: "main", entry_symbol: "main.main", functions: functions, calls: [edge], globals: globals }
    emitted := emit_function_ssa_amd64(program)
    if emitted.error != "" { eprintln(emitted.error); return 1 }
    args := host_args()
    if len(args) > 1 { println(emitted.assembly); return 0 }
    startup := amd64_executable_startup(program)
    if startup.error != "" { eprintln(startup.error); return 2 }
    assembly := emitted.assembly + startup.assembly
    println(assembly)
    return 0
}
