package compile.internal.ir.lower

import (
    "compile.internal.ast"
    "compile.internal.mir"
    "std"
    "std.option"
    "std.prelude"
)

// This adapter consumes canonical AST objects. It never evaluates source main,
// serializes an expression back to source, or synthesizes a constant result.
struct program_lower_state {
    mir_program_instruction[] instructions
    string[] binding_names
    int[] binding_values
    int next_value
    int expression_value
    string error
}

struct program_function_lower_result {
    mir_program_function function_value
    string error
}

func program_item_package(source_file src, int index) string {
    if index < len(src.item_packages) && src.item_packages[index] != "" {
        return src.item_packages[index]
    }
    return src.pkg
}

func program_signature(string package_name, function_decl declaration) mir_program_function {
    params := mir_program_parameter[]()
    i := 0
    for i < len(declaration.sig.params) {
        parameter := declaration.sig.params[i]
        params = append(params, mir_program_parameter {
            value_id: i, name: parameter.name, type_name: parameter.type_name,
        })
        i = i + 1
    }
    results := string[]()
    if declaration.sig.return_type.is_some() {
        result_type := declaration.sig.return_type.unwrap()
        if result_type != "" && result_type != "()" { results = append(results, result_type) }
    }
    return mir_program_function {
        symbol: package_name + "." + declaration.sig.name, params: params,
        result_types: results, blocks: mir_program_block[](), external: declaration.body.is_none(),
    }
}

func program_binding_index(program_lower_state state, string name) int {
    i := len(state.binding_names)
    for i > 0 {
        i = i - 1
        if state.binding_names[i] == name { return i }
    }
    return -1
}

func program_expression_type(program_lower_state state, mir_program_function signature, int id) string {
    i := 0
    for i < len(signature.params) {
        if signature.params[i].value_id == id { return signature.params[i].type_name }
        i = i + 1
    }
    i = 0
    for i < len(state.instructions) {
        instruction := state.instructions[i]
        r := 0
        for r < len(instruction.result_ids) {
            if instruction.result_ids[r] == id { return instruction.result_types[r] }
            r = r + 1
        }
        i = i + 1
    }
    return ""
}

func program_callee_path(expr callee) string {
    switch callee {
        expr.name(name) : { return name.name }
        expr.member(member) : {
            root := program_callee_path(member.target.value)
            if root == "" { return "" }
            return root + "." + member.member
        }
        _ : { return "" },
    }
}

func program_is_qualified(string name) bool {
    i := 0
    for i < len(name) {
        if std.prelude.char_at(name, i) == "." { return true }
        i = i + 1
    }
    return false
}

func program_emit_integer(program_lower_state state, string literal) program_lower_state {
    // Canonical int_expr retains token spelling. Only the implemented decimal
    // range is accepted here; other spellings require an explicit lowering.
    value := 0
    i := 0
    if literal == "" { state.error = "empty integer literal"; return state }
    for i < len(literal) {
        ch := std.prelude.char_at(literal, i)
        digit := -1
        if ch == "0" { digit = 0 }
        if ch == "1" { digit = 1 }
        if ch == "2" { digit = 2 }
        if ch == "3" { digit = 3 }
        if ch == "4" { digit = 4 }
        if ch == "5" { digit = 5 }
        if ch == "6" { digit = 6 }
        if ch == "7" { digit = 7 }
        if ch == "8" { digit = 8 }
        if ch == "9" { digit = 9 }
        if digit < 0 { state.error = "unsupported integer spelling: " + literal; return state }
        if value > 922337203685477580 || (value == 922337203685477580 && digit > 7) {
            state.error = "integer literal exceeds int64: " + literal
            return state
        }
        value = value * 10 + digit
        i = i + 1
    }
    id := state.next_value
    state.next_value = id + 1
    state.instructions = append(state.instructions, mir_program_instruction {
        op: "const_int", result_ids: int[]{id}, result_types: string[]{"int"},
        operands: int[](), integer_value: value, symbol: "",
    })
    state.expression_value = id
    return state
}

func program_binary_opcode(string op) string {
    if op == "+" { return "add" }
    if op == "-" { return "sub" }
    if op == "*" { return "mul" }
    if op == "/" { return "div" }
    if op == "%" { return "mod" }
    return ""
}

func program_lower_expression(expr expression, string package_name, mir_program_function[] signatures, program_lower_state initial_state) program_lower_state {
    state := initial_state
    if state.error != "" { return state }
    switch expression {
        expr.int(literal) : { return program_emit_integer(state, literal.value) }
        expr.name(name) : {
            binding := program_binding_index(state, name.name)
            if binding < 0 { state.error = "undefined binding: " + name.name; return state }
            state.expression_value = state.binding_values[binding]
            return state
        }
        expr.binary(binary) : {
            op := program_binary_opcode(binary.op)
            if op == "" { state.error = "unsupported binary operation: " + binary.op; return state }
            state = program_lower_expression(binary.left.value, package_name, signatures, state)
            if state.error != "" { return state }
            left := state.expression_value
            state = program_lower_expression(binary.right.value, package_name, signatures, state)
            if state.error != "" { return state }
            right := state.expression_value
            id := state.next_value
            state.next_value = id + 1
            state.instructions = append(state.instructions, mir_program_instruction {
                op: op, result_ids: int[]{id}, result_types: string[]{"int"},
                operands: int[]{left, right}, integer_value: 0, symbol: "",
            })
            state.expression_value = id
            return state
        }
        expr.call(call) : {
            if len(call.type_args) != 0 { state.error = "generic call requires monomorphization"; return state }
            path := program_callee_path(call.callee.value)
            if path == "" { state.error = "call requires a resolved direct callee"; return state }
            symbol := ""
            if call.resolved_callee.is_some() { symbol = call.resolved_callee.unwrap() }
            if program_is_qualified(path) {
                if mir_program_function_index(signatures, path) >= 0 {
                    symbol = path
                } else {
                    if !program_is_qualified(symbol) || mir_program_function_index(signatures, symbol) < 0 {
                        state.error = "qualified call requires package identity: " + path
                        return state
                    }
                }
            } else {
                if symbol == "" { symbol = path }
                if !program_is_qualified(symbol) { symbol = package_name + "." + symbol }
            }
            target := mir_program_function_index(signatures, symbol)
            if target < 0 { state.error = "unknown callee: " + symbol; return state }
            args := int[]()
            i := 0
            for i < len(call.args) {
                state = program_lower_expression(call.args[i], package_name, signatures, state)
                if state.error != "" { return state }
                args = append(args, state.expression_value)
                i = i + 1
            }
            result_types := signatures[target].result_types
            if len(result_types) > 1 { state.error = "multiple-result expression requires explicit binding"; return state }
            result_ids := int[]()
            state.expression_value = -1
            if len(result_types) == 1 {
                state.expression_value = state.next_value
                result_ids = append(result_ids, state.next_value)
                state.next_value = state.next_value + 1
            }
            state.instructions = append(state.instructions, mir_program_instruction {
                op: "call", result_ids: result_ids, result_types: result_types,
                operands: args, integer_value: 0, symbol: symbol,
            })
            return state
        }
        _ : { state.error = "unsupported P1 expression"; return state },
    }
}

func program_lower_function(string package_name, function_decl declaration, mir_program_function signature, mir_program_function[] signatures) program_function_lower_result {
    output := program_function_lower_result { function_value: signature, error: "" }
    if len(declaration.sig.generics) != 0 { output.error = "generic function requires monomorphization: " + signature.symbol; return output }
    if declaration.sig.return_type.is_some() {
        descriptor := declaration.sig.return_type.unwrap()
        if descriptor != "()" && len(descriptor) > 0 && std.prelude.char_at(descriptor, 0) == "(" {
            output.error = "multiple-return signature requires explicit result lowering: " + signature.symbol
            return output
        }
    }
    if declaration.body.is_none() { return output }
    state := program_lower_state {
        instructions: mir_program_instruction[](), binding_names: string[](), binding_values: int[](),
        next_value: len(signature.params), expression_value: -1, error: "",
    }
    i := 0
    for i < len(signature.params) {
        state.binding_names = append(state.binding_names, signature.params[i].name)
        state.binding_values = append(state.binding_values, signature.params[i].value_id)
        i = i + 1
    }
    body := declaration.body.unwrap()
    returned := false
    returns := int[]()
    i = 0
    for i < len(body.statements) {
        if returned { output.error = "statement after return: " + signature.symbol; return output }
        switch body.statements[i] {
            stmt.let(binding) : {
                if program_binding_index(state, binding.name) >= 0 { output.error = "duplicate binding: " + binding.name; return output }
                state = program_lower_expression(binding.value, package_name, signatures, state)
                if state.error == "" && state.expression_value < 0 { state.error = "cannot bind a void call" }
                if state.error == "" && binding.type_name.is_some() {
                    if binding.type_name.unwrap() != program_expression_type(state, signature, state.expression_value) {
                        state.error = "local type mismatch: " + binding.name
                    }
                }
                state.binding_names = append(state.binding_names, binding.name)
                state.binding_values = append(state.binding_values, state.expression_value)
            }
            stmt.expr(value) : { state = program_lower_expression(value.expr, package_name, signatures, state) }
            stmt.return(value) : {
                if value.value.is_some() {
                    if len(signature.result_types) == 0 { output.error = "unexpected return value: " + signature.symbol; return output }
                    state = program_lower_expression(value.value.unwrap(), package_name, signatures, state)
                    if state.error == "" && state.expression_value < 0 { state.error = "return expression has no value: " + signature.symbol }
                    returns = append(returns, state.expression_value)
                }
                returned = true
            }
            _ : { output.error = "unsupported P1 statement in: " + signature.symbol; return output },
        }
        if state.error != "" { output.error = state.error; return output }
        i = i + 1
    }
    if returned && body.final_expr.is_some() {
        output.error = "expression after return: " + signature.symbol
        return output
    }
    if !returned && body.final_expr.is_some() {
        state = program_lower_expression(body.final_expr.unwrap(), package_name, signatures, state)
        if state.error != "" { output.error = state.error; return output }
        if state.expression_value >= 0 { returns = append(returns, state.expression_value) }
    }
    blocks := mir_program_block[]()
    block := mir_program_block{
        id: 0, instructions: state.instructions, terminator: "return", return_values: returns,
    }
    blocks = append(blocks, block)
    output.function_value.blocks = blocks
    return output
}

func lower_source_program(source_file src) mir_program_result {
    empty := mir_program { package_name: src.pkg, entry_symbol: src.pkg + ".main", functions: mir_program_function[](), calls: mir_program_call[]() }
    result := mir_program_result { program: empty, error: "" }
    if len(src.item_packages) != 0 && len(src.item_packages) != len(src.items) {
        result.error = "source item package count mismatch"
        return result
    }
    signatures := mir_program_function[]()
    i := 0
    for i < len(src.items) {
        switch src.items[i] {
            item.function(declaration) : {
                signatures = append(signatures, program_signature(program_item_package(src, i), declaration))
            }
            _ : { result.error = "P1 requires explicit lowering for non-function declarations"; return result },
        }
        i = i + 1
    }
    functions := mir_program_function[]()
    i = 0
    for i < len(src.items) {
        switch src.items[i] {
            item.function(declaration) : {
                lowered := program_lower_function(program_item_package(src, i), declaration, signatures[i], signatures)
                if lowered.error != "" { result.error = lowered.error; return result }
                functions = append(functions, lowered.function_value)
            }
            _ : (),
        }
        i = i + 1
    }
    return lower_mir_program(src.pkg, src.pkg + ".main", functions)
}
