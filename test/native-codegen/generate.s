package native_codegen_test

func native_value(int id, string op, int[] operands, int literal, int parameter) function_ssa_value {
    return function_ssa_value {
        id: id, op: op, operands: operands, block_id: 41, type_name: "int",
        integer_value: literal, parameter_index: parameter,
    }
}

// Returning the array snapshots record identities in the bootstrap host.
func native_append(function_ssa_value[] values, function_ssa_value value) function_ssa_value[] {
    values.push(value)
    return values
}

func native_function(string symbol, string[] parameters, function_ssa_value[] values, int returned) function_ssa_function {
    results := string[]{"int"}
    returns := int[]{returned}
    if returned < 0 { results = string[](); returns = int[]() }
    blocks := function_ssa_block[]()
    blocks.push(function_ssa_block {
        id: 41, label: "entry", values: values, predecessors: int[](), successors: int[](),
        terminator: "return", terminator_values: returns,
    })
    return function_ssa_function {
        symbol: symbol, parameter_types: parameters, result_types: results,
        blocks: blocks, entry_block: 41, exit_block: 41,
    }
}

func main() int {
    args := host_args()
    mode := "base"
    if len(args) > 1 { mode = args[1] }
    // Sparse IDs and arbitrary punctuation never become frame offsets/symbols.
    input_id := 1000000000000
    entry_symbol := "sample.main$unsafe;symbol"
    target_symbol := "sample.helper/forward"
    values := function_ssa_value[]()
    values = native_append(values, native_value(input_id, "param", int[](), 0, 0))
    values = native_append(values, native_value(21, "const_int", int[](), 3, 0))
    literal := 4
    if mode == "changed" { literal = 9 }
    values = native_append(values, native_value(22, "const_int", int[](), literal, 0))
    values = native_append(values, native_value(23, "call", int[]{input_id, 21}, 0, 0))
    values = native_append(values, native_value(24, "add", int[]{23, input_id}, 0, 0))
    op := "add"
    if mode == "subtract" { op = "sub" }
    values = native_append(values, native_value(25, op, int[]{24, 22}, 0, 0))
    returned := 25
    if mode == "copy" {
        values = native_append(values, native_value(26, "copy", int[]{25}, 0, 0))
        returned = 26
    }
    helper := function_ssa_value[]()
    // Deliberately reverse param storage order to test parameter_index.
    helper = native_append(helper, native_value(200, "param", int[](), 0, 1))
    helper = native_append(helper, native_value(100, "param", int[](), 0, 0))
    helper = native_append(helper, native_value(300, "mul", int[]{100, 200}, 0, 0))
    functions := function_ssa_function[]()
    functions.push(native_function(entry_symbol, string[]{"int"}, values, returned))
    functions.push(native_function(target_symbol, string[]{"int", "int"}, helper, 300))
    unused := function_ssa_value[]()
    unused = native_append(unused, native_value(999999999999, "const_int", int[](), -7, 0))
    functions.push(native_function("uncalled.main", string[](), unused, 999999999999))
    calls := function_ssa_call[]()
    calls.push(function_ssa_call { caller: entry_symbol, callee: target_symbol, block_id: 41, value_id: 23 })
    if mode == "min" || mode == "max" {
        literal = -9223372036854775807 - 1
        if mode == "max" { literal = 9223372036854775807 }
        values = function_ssa_value[]()
        values = native_append(values, native_value(input_id, "param", int[](), 0, 0))
        values = native_append(values, native_value(25, "const_int", int[](), literal, 0))
        functions[0] = native_function(entry_symbol, string[]{"int"}, values, 25)
        calls = function_ssa_call[]()
    }
    if mode == "divide" || mode == "modulo" || mode == "positive_divide" || mode == "positive_modulo" || mode == "divide_zero" || mode == "divide_minus_one" || mode == "modulo_minus_one" || mode == "wrap" || mode == "subwrap" || mode == "mulwrap" || mode == "identity" {
        values = function_ssa_value[]()
        values = native_append(values, native_value(input_id, "param", int[](), 0, 0))
        divisor := -3
        if mode == "positive_divide" || mode == "positive_modulo" || mode == "mulwrap" { divisor = 3 }
        if mode == "divide_zero" { divisor = 0 }
        if mode == "divide_minus_one" || mode == "modulo_minus_one" { divisor = -1 }
        if mode == "wrap" || mode == "subwrap" { divisor = 1 }
        values = native_append(values, native_value(21, "const_int", int[](), divisor, 0))
        op = "div"
        if mode == "modulo" || mode == "positive_modulo" || mode == "modulo_minus_one" { op = "mod" }
        if mode == "wrap" { op = "add" }
        if mode == "subwrap" { op = "sub" }
        if mode == "mulwrap" { op = "mul" }
        operands := int[]{input_id, 21}
        if mode == "identity" { op = "copy"; operands = int[]{input_id} }
        values = native_append(values, native_value(25, op, operands, 0, 0))
        functions[0] = native_function(entry_symbol, string[]{"int"}, values, 25)
        calls = function_ssa_call[]()
    }
    if mode == "call7" || mode == "call8" || mode == "incoming8" {
        count := 8
        if mode == "call7" { count = 7 }
        helper = function_ssa_value[]()
        parameters := string[]()
        p := count - 1
        for p >= 0 {
            helper = native_append(helper, native_value(100 + p, "param", int[](), 0, p))
            p = p - 1
        }
        total := 100
        p = 0
        for p < count {
            parameters.push("int")
            if p > 0 {
                helper = native_append(helper, native_value(200 + p, "const_int", int[](), p + 1, 0))
                parameter_id := 100 + p
                constant_id := 200 + p
                multiplied_id := 300 + p
                helper = native_append(helper, native_value(multiplied_id, "mul", int[]{parameter_id, constant_id}, 0, 0))
                helper = native_append(helper, native_value(400 + p, "add", int[]{total, multiplied_id}, 0, 0))
                total = 400 + p
            }
            p = p + 1
        }
        functions[1] = native_function(target_symbol, parameters, helper, total)
        if mode == "incoming8" {
            functions[0] = native_function(entry_symbol, parameters, helper, total)
            calls = function_ssa_call[]()
        } else {
            values = function_ssa_value[]()
            values = native_append(values, native_value(input_id, "param", int[](), 0, 0))
            operands := int[]{input_id}
            p = 1
            for p < count {
                constant := native_value(p, "const_int", int[](), p + 1, 0)
                values = native_append(values, constant)
                operands.push(p)
                p = p + 1
            }
            values = native_append(values, native_value(23, "call", operands, 0, 0))
            functions[0] = native_function(entry_symbol, string[]{"int"}, values, 23)
        }
    }
    if mode == "nested" {
        // A forward helper calls another helper; its two parameters and local
        // constant remain live after the nested call clobbers caller registers.
        helper = function_ssa_value[]()
        helper = native_append(helper, native_value(100, "param", int[](), 0, 0))
        helper = native_append(helper, native_value(200, "param", int[](), 0, 1))
        helper = native_append(helper, native_value(201, "const_int", int[](), 5, 0))
        helper = native_append(helper, native_value(300, "call", int[]{100, 200}, 0, 0))
        helper = native_append(helper, native_value(301, "add", int[]{300, 100}, 0, 0))
        helper = native_append(helper, native_value(302, "add", int[]{301, 200}, 0, 0))
        helper = native_append(helper, native_value(303, "add", int[]{302, 201}, 0, 0))
        functions[1] = native_function(target_symbol, string[]{"int", "int"}, helper, 303)
        last := function_ssa_value[]()
        last = native_append(last, native_value(0, "param", int[](), 0, 0))
        last = native_append(last, native_value(1, "param", int[](), 0, 1))
        last = native_append(last, native_value(2, "mul", int[]{0, 1}, 0, 0))
        functions.push(native_function("last", string[]{"int", "int"}, last, 2))
        calls.push(function_ssa_call { caller: target_symbol, callee: "last", block_id: 41, value_id: 300 })
    }
    if mode == "void" || mode == "void_call" || mode == "zero" {
        values = function_ssa_value[]()
        calls = function_ssa_call[]()
        if mode != "zero" {
            value := native_value(99, "call", int[](), 0, 0)
            value.type_name = "void"
            values.push(value)
            functions[1] = native_function(target_symbol, string[](), function_ssa_value[](), -1)
            calls.push(function_ssa_call { caller: entry_symbol, callee: target_symbol, block_id: 41, value_id: 99 })
        }
        if mode == "void" {
            functions[0] = native_function(entry_symbol, string[](), values, -1)
        } else {
            values = native_append(values, native_value(100, "const_int", int[](), 17, 0))
            functions[0] = native_function(entry_symbol, string[](), values, 100)
        }
    }
    if mode == "invalid_op" { functions[0].blocks[0].values[1].op = "unimplemented" }
    if mode == "undefined" { functions[0].blocks[0].values[3].operands = int[]{999} }
    if mode == "bad_arity" { functions[0].blocks[0].values[4].operands = int[]{23} }
    if mode == "bad_copy_arity" { functions[0].blocks[0].values[4].op = "copy" }
    if mode == "const_operands" { functions[0].blocks[0].values[1].operands = int[]{input_id} }
    if mode == "forward_operand" { functions[0].blocks[0].values[4].operands = int[]{25, 23} }
    if mode == "bad_parameter_type" { functions[2].parameter_types = string[]{"string"} }
    if mode == "bad_param" { functions[0].blocks[0].values[0].parameter_index = 1 }
    if mode == "missing_param" { functions[0].blocks[0].values[0].op = "const_int" }
    if mode == "duplicate_param" { functions[0].blocks[0].values[1].op = "param" }
    if mode == "param_operands" { functions[0].blocks[0].values[1].op = "param"; functions[0].blocks[0].values[1].parameter_index = 1; functions[0].parameter_types.push("int"); functions[0].blocks[0].values[1].operands = int[]{input_id} }
    if mode == "bad_type" { functions[2].blocks[0].values[0].type_name = "string"; functions[2].result_types = string[]{"string"} }
    if mode == "bad_return" { functions[0].blocks[0].terminator_values = int[]{999} }
    if mode == "multiple_results" { functions[0].result_types = string[]{"int", "int"}; functions[0].blocks[0].terminator_values = int[]{25, 25} }
    if mode == "missing_edge" { calls = function_ssa_call[]() }
    if mode == "unknown_target" { calls[0].callee = "missing" }
    if mode == "bad_call_result" { functions[0].blocks[0].values[3].type_name = "void" }
    if mode == "void_operand" { functions[0].blocks[0].values[1].type_name = "void" }
    if mode == "void_use" {
        functions[1].result_types = string[]()
        functions[1].blocks[0].terminator_values = int[]()
        functions[0].blocks[0].values[3].type_name = "void"
    }
    if mode == "multiple_blocks" {
        extra_values := function_ssa_value[]()
        extra_values = native_append(extra_values, native_value(1234, "const_int", int[](), 1, 0))
        empty := native_function("temp", string[](), extra_values, 1234).blocks[0]
        empty.id = 42
        empty.values[0].block_id = 42
        empty.label = "unreachable"
        functions[0].blocks.push(empty)
    }
    program := function_ssa_program {
        package_name: "sample", entry_symbol: entry_symbol, functions: functions, calls: calls,
    }
    emitted := emit_function_ssa_amd64(program)
    if emitted.error != "" {
        if emitted.assembly != "" { eprintln("failed emission leaked partial assembly"); return 2 }
        eprintln(emitted.error)
        return 1
    }
    if len(args) > 2 && args[2] == "startup" {
        startup := amd64_executable_startup(program)
        if startup.error != "" {
            if startup.assembly != "" { eprintln("failed startup leaked partial assembly"); return 2 }
            eprintln(startup.error)
            return 1
        }
        println(emitted.assembly + startup.assembly)
    } else {
        println(emitted.assembly)
    }
    return 0
}
