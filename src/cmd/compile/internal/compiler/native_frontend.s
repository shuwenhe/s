package compile.compiler

// The executable frontend accepts the documented straight-line integer subset.
// It shares the compiler's token scanner, then constructs structured MIR from
// tokens. The legacy C frontend and canonical AST adapter remain separate.
struct native_parser {
    compiler_state lex
    string package_name
    mir_program_function[] functions
    int[] body_positions
    int[] body_lines
    string[] binding_names
    int[] binding_values
    mir_program_instruction[] instructions
    int next_value
    int expression_value
    string expression_type
    int[] return_values
    bool returned
    int function_index
    string error
}

func native_fail(native_parser initial, string message) native_parser {
    state := initial
    if state.error == "" { state.error = "native frontend:" + compiler_number(state.lex.line) + ": " + message }
    return state
}

func native_advance(native_parser initial) native_parser {
    state := initial
    state.lex = compiler_next(state.lex)
    if state.lex.error != "" { return native_fail(state, state.lex.error) }
    return state
}

func native_expect(native_parser initial, string expected) native_parser {
    state := initial
    if state.error != "" { return state }
    if state.lex.token != expected { return native_fail(state, "expected '" + expected + "', found '" + state.lex.token + "'") }
    return native_advance(state)
}

func native_semicolon(native_parser initial) native_parser {
    state := initial
    if state.lex.token == ";" { return native_advance(state) }
    return state
}

func native_identifier(string token) bool {
    if !compiler_ident(token) { return false }
    // Match the canonical keyword vocabulary in lexer/token/token.s. The
    // shared scanner stores token spelling rather than a keyword token kind.
    if token == "package" || token == "use" || token == "as" || token == "pub" || token == "func" || token == "const" || token == "var" || token == "static" { return false }
    if token == "struct" || token == "enum" || token == "trait" || token == "for" || token == "if" || token == "else" || token == "while" { return false }
    if token == "switch" || token == "select" || token == "case" || token == "default" || token == "return" || token == "break" || token == "continue" || token == "sroutine" { return false }
    if token == "true" || token == "false" || token == "nil" || token == "unsafe" || token == "extern" || token == "where" || token == "in" { return false }
    if token == "int" || token == "bool" || token == "string" || token == "import" || token == "defer" { return false }
    return true
}

func native_parse_package(native_parser initial) native_parser {
    state := initial
    state = native_expect(state, "package")
    if state.error != "" { return state }
    if !native_identifier(state.lex.token) { return native_fail(state, "expected package name") }
    state.package_name = state.lex.token
    state = native_advance(state)
    for state.error == "" && state.lex.token == "." {
        state = native_advance(state)
        if !native_identifier(state.lex.token) { return native_fail(state, "expected package component") }
        state.package_name = state.package_name + "." + state.lex.token
        state = native_advance(state)
    }
    return native_semicolon(state)
}

func native_append_parameter(mir_program_parameter[] initial, string name) mir_program_parameter[] {
    params := initial
    params.push(mir_program_parameter { value_id: len(params), name: name, type_name: "int" })
    return params
}

func native_parse_signature(native_parser initial) native_parser {
    state := initial
    state = native_expect(state, "func")
    if state.error != "" { return state }
    if !native_identifier(state.lex.token) { return native_fail(state, "expected function name") }
    symbol := state.package_name + "." + state.lex.token
    if mir_program_function_index(state.functions, symbol) >= 0 { return native_fail(state, "duplicate function: " + symbol) }
    state = native_expect(native_advance(state), "(")
    params := mir_program_parameter[]()
    for state.error == "" && state.lex.token != ")" && state.lex.token != "" {
        if len(params) > 0 { state = native_expect(state, ",") }
        if state.lex.token != "int" { return native_fail(state, "native parameters require int") }
        state = native_advance(state)
        if !native_identifier(state.lex.token) { return native_fail(state, "expected parameter name") }
        parameter_name := state.lex.token
        previous := 0
        for previous < len(params) {
            if params[previous].name == parameter_name { return native_fail(state, "duplicate parameter: " + parameter_name) }
            previous = previous + 1
        }
        params = native_append_parameter(params, parameter_name)
        state = native_advance(state)
    }
    state = native_expect(state, ")")
    results := string[]()
    if state.lex.token == "int" {
        results.push("int")
        state = native_advance(state)
    } else if state.lex.token == "(" {
        state = native_expect(native_advance(state), ")")
    }
    if state.error != "" { return state }
    if state.lex.token != "{" { return native_fail(state, "native function requires a body and int or void result") }
    state.functions.push(mir_program_function {
        symbol: symbol, params: params, result_types: results,
        blocks: mir_program_block[](), external: false,
    })
    // compiler_next leaves pos immediately after its current token.
    state.body_positions.push(state.lex.pos)
    state.body_lines.push(state.lex.line)
    depth := 1
    state = native_advance(state)
    for state.error == "" && depth > 0 && state.lex.token != "" {
        if state.lex.token == "{" { depth = depth + 1 }
        if state.lex.token == "}" { depth = depth - 1 }
        state = native_advance(state)
    }
    if depth != 0 { return native_fail(state, "unterminated function body") }
    return native_semicolon(state)
}

func native_binding_index(native_parser initial, string name) int {
    state := initial
    i := 0
    for i < len(state.binding_names) {
        if state.binding_names[i] == name { return i }
        i = i + 1
    }
    return -1
}

func native_emit_integer(native_parser initial, int value) native_parser {
    state := initial
    id := state.next_value
    state.next_value = id + 1
    state.instructions.push(mir_program_instruction {
        op: "const_int", result_ids: int[]{id}, result_types: string[]{"int"},
        operands: int[](), integer_value: value, symbol: "",
    })
    state.expression_value = id
    state.expression_type = "int"
    return state
}

func native_decimal_digit(string token) int {
    digits := "0123456789"
    i := 0
    for i < 10 {
        if token == __host_char_at(digits, i) { return i }
        i = i + 1
    }
    return -1
}

func native_hex_digit(string token) int {
    if token == "0" { return 0 }
    if token == "1" { return 1 }
    if token == "2" { return 2 }
    if token == "3" { return 3 }
    if token == "4" { return 4 }
    if token == "5" { return 5 }
    if token == "6" { return 6 }
    if token == "7" { return 7 }
    if token == "8" { return 8 }
    if token == "9" { return 9 }
    if token == "a" || token == "A" { return 10 }
    if token == "b" || token == "B" { return 11 }
    if token == "c" || token == "C" { return 12 }
    if token == "d" || token == "D" { return 13 }
    if token == "e" || token == "E" { return 14 }
    if token == "f" || token == "F" { return 15 }
    return -1
}

func native_parse_integer(native_parser initial, bool negative) native_parser {
    state := initial
    token := state.lex.token
    
    // Check for hexadecimal prefix
    if len(token) >= 3 && __host_char_at(token, 0) == "0" && 
       (__host_char_at(token, 1) == "x" || __host_char_at(token, 1) == "X") {
        // Hexadecimal literal
        value := 0
        i := 2
        for i < len(token) {
            ch := __host_char_at(token, i)
            if ch == "_" {
                i = i + 1
                continue
            }
            digit := native_hex_digit(ch)
            if digit < 0 { return native_fail(state, "unsupported integer literal: " + token) }
            // Check overflow: value * 16
            if value < -922337203685477580 / 16 { return native_fail(state, "integer literal exceeds int64") }
            value = value * 16 - digit
            i = i + 1
        }
        if !negative { value = 0 - value }
        state = native_emit_integer(state, value)
        return native_advance(state)
    }
    
    // Decimal literal
    // Accumulate negatively so the magnitude of INT64_MIN never overflows.
    value := 0
    i := 0
    for i < len(token) {
        ch := __host_char_at(token, i)
        if ch == "_" {
            i = i + 1
            continue
        }
        digit := native_decimal_digit(ch)
        if digit < 0 { return native_fail(state, "unsupported integer literal: " + token) }
        if value < -922337203685477580 { return native_fail(state, "integer literal exceeds int64") }
        if value == -922337203685477580 {
            limit := 7
            if negative { limit = 8 }
            if digit > limit { return native_fail(state, "integer literal exceeds int64") }
        }
        value = value * 10 - digit
        i = i + 1
    }
    if !negative { value = 0 - value }
    state = native_emit_integer(state, value)
    return native_advance(state)
}

func native_emit_binary(native_parser initial, string op, int left, int right) native_parser {
    state := initial
    id := state.next_value
    state.next_value = id + 1
    state.instructions.push(mir_program_instruction {
        op: op, result_ids: int[]{id}, result_types: string[]{"int"},
        operands: int[]{left, right}, integer_value: 0, symbol: "",
    })
    state.expression_value = id
    state.expression_type = "int"
    return state
}

func native_call(native_parser initial, string path) native_parser {
    state := initial
    symbol := path
    if !compiler_contains_text(symbol, ".") { symbol = state.package_name + "." + symbol }
    target := mir_program_function_index(state.functions, symbol)
    if target < 0 { return native_fail(state, "unknown callee: " + symbol) }
    signature := state.functions[target]
    state = native_expect(state, "(")
    operands := int[]()
    for state.error == "" && state.lex.token != ")" && state.lex.token != "" {
        if len(operands) > 0 { state = native_expect(state, ",") }
        state = native_expression(state, 1)
        if state.error != "" { return state }
        if state.expression_type != "int" { return native_fail(state, "call argument requires int: " + symbol) }
        operands.push(state.expression_value)
    }
    state = native_expect(state, ")")
    if state.error != "" { return state }
    if len(operands) != len(signature.params) { return native_fail(state, "call argument count: " + symbol) }
    results := int[]()
    state.expression_value = -1
    state.expression_type = "void"
    if len(signature.result_types) > 0 {
        results.push(state.next_value)
        state.expression_value = state.next_value
        state.expression_type = "int"
        state.next_value = state.next_value + 1
    }
    state.instructions.push(mir_program_instruction {
        op: "call", result_ids: results, result_types: signature.result_types,
        operands: operands, integer_value: 0, symbol: symbol,
    })
    return state
}

func native_minimum_magnitude(string token) bool {
    i := 0
    for i + 1 < len(token) && __host_char_at(token, i) == "0" { i = i + 1 }
    return __host_slice(token, i, len(token)) == "9223372036854775808"
}

func native_atom(native_parser initial) native_parser {
    state := initial
    if state.error != "" { return state }
    token := state.lex.token
    if token == "-" {
        state = native_advance(state)
        // The minimum's magnitude is not a positive int64 value. Every other
        // unary minus remains a runtime subtraction instruction.
        if native_minimum_magnitude(state.lex.token) { return native_parse_integer(state, true) }
        state = native_emit_integer(state, 0)
        zero := state.expression_value
        state = native_atom(state)
        if state.error != "" { return state }
        if state.expression_type != "int" { return native_fail(state, "unary minus requires int") }
        return native_emit_binary(state, "sub", zero, state.expression_value)
    }
    if token == "(" {
        state = native_expression(native_advance(state), 1)
        return native_expect(state, ")")
    }
    if compiler_digit(__host_char_at(token, 0)) { return native_parse_integer(state, false) }
    if !native_identifier(token) { return native_fail(state, "unsupported expression: " + token) }
    state = native_advance(state)
    path := token
    for state.error == "" && state.lex.token == "." {
        state = native_advance(state)
        if !native_identifier(state.lex.token) { return native_fail(state, "expected qualified function component") }
        path = path + "." + state.lex.token
        state = native_advance(state)
    }
    if state.lex.token == "(" {
        if native_binding_index(state, token) >= 0 {
            return native_fail(state, "integer binding is not callable: " + token)
        }
        return native_call(state, path)
    }
    slot := native_binding_index(state, path)
    if slot < 0 { return native_fail(state, "unknown binding: " + path) }
    state.expression_value = state.binding_values[slot]
    state.expression_type = "int"
    return state
}

func native_binary_precedence(string token) int {
    if token == "+" || token == "-" { return 1 }
    if token == "*" || token == "/" || token == "%" { return 2 }
    return 0
}

func native_binary_op(string token) string {
    if token == "+" { return "add" }
    if token == "-" { return "sub" }
    if token == "*" { return "mul" }
    if token == "/" { return "div" }
    return "mod"
}

func native_expression(native_parser initial, int minimum) native_parser {
    state := initial
    state = native_atom(state)
    for state.error == "" && native_binary_precedence(state.lex.token) >= minimum {
        token := state.lex.token
        precedence := native_binary_precedence(token)
        if state.expression_type != "int" { return native_fail(state, "binary operand requires int") }
        left := state.expression_value
        state = native_expression(native_advance(state), precedence + 1)
        if state.error != "" { return state }
        if state.expression_type != "int" { return native_fail(state, "binary operand requires int") }
        state = native_emit_binary(state, native_binary_op(token), left, state.expression_value)
    }
    return state
}

func native_binding_statement(native_parser initial, string name, bool declaration) native_parser {
    state := initial
    slot := native_binding_index(state, name)
    if declaration && slot >= 0 { return native_fail(state, "duplicate binding: " + name) }
    if !declaration && slot < 0 { return native_fail(state, "assignment to unknown binding: " + name) }
    state = native_expression(state, 1)
    if state.error != "" { return state }
    if state.expression_type != "int" { return native_fail(state, "binding requires int: " + name) }
    if declaration {
        state.binding_names.push(name)
        state.binding_values.push(state.expression_value)
    } else {
        state.binding_values[slot] = state.expression_value
    }
    return native_semicolon(state)
}

func native_statement(native_parser initial) native_parser {
    state := initial
    token := state.lex.token
    if token == "return" {
        state = native_advance(state)
        signature := state.functions[state.function_index]
        if len(signature.result_types) == 0 {
            if state.lex.token == "(" { state = native_expect(native_advance(state), ")") }
            if state.lex.token != ";" && state.lex.token != "}" { return native_fail(state, "void function cannot return a value") }
        } else {
            state = native_expression(state, 1)
            if state.error != "" { return state }
            if state.expression_type != "int" { return native_fail(state, "integer function must return int") }
            state.return_values.push(state.expression_value)
        }
        state.returned = true
        return native_semicolon(state)
    }
    if token == "int" {
        state = native_advance(state)
        if !native_identifier(state.lex.token) { return native_fail(state, "expected binding name") }
        name := state.lex.token
        state = native_expect(native_advance(state), "=")
        return native_binding_statement(state, name, true)
    }
    if !native_identifier(token) { return native_fail(state, "unsupported native statement: " + token) }
    after_name := native_advance(state)
    if after_name.lex.token == ":=" || after_name.lex.token == "=" {
        declaration := after_name.lex.token == ":="
        return native_binding_statement(native_advance(after_name), token, declaration)
    }
    // A standalone direct call may discard an integer result or return void.
    if after_name.lex.token != "(" && after_name.lex.token != "." { return native_fail(state, "expected binding assignment or direct call") }
    state = native_atom(state)
    if state.error != "" { return state }
    return native_semicolon(state)
}

func native_parse_body(native_parser initial, int index) native_parser {
    state := initial
    source := state.lex.source
    state.lex = compiler_state {
        source: source, pos: state.body_positions[index], line: state.body_lines[index],
        token: "{", error: "",
    }
    state.binding_names = string[]()
    state.binding_values = int[]()
    state.instructions = mir_program_instruction[]()
    state.return_values = int[]()
    state.returned = false
    state.function_index = index
    signature := state.functions[index]
    state.next_value = len(signature.params)
    p := 0
    for p < len(signature.params) {
        state.binding_names.push(signature.params[p].name)
        state.binding_values.push(signature.params[p].value_id)
        p = p + 1
    }
    state = native_expect(state, "{")
    for state.error == "" && state.lex.token != "}" && state.lex.token != "" {
        if state.returned { return native_fail(state, "statement after return is unsupported") }
        state = native_statement(state)
    }
    state = native_expect(state, "}")
    if state.error != "" { return state }
    if !state.returned && len(signature.result_types) > 0 { return native_fail(state, "integer function requires return: " + signature.symbol) }
    block := mir_program_block {
        id: 0, instructions: state.instructions, terminator: "return", return_values: state.return_values,
    }
    blocks := mir_program_block[]()
    blocks.push(block)
    signature.blocks = blocks
    state.functions[index] = signature
    return state
}

func native_source_to_mir(string source) mir_program_result {
    state := native_parser {
        lex: compiler_state { source: source, pos: 0, line: 1, token: "", error: "" },
        package_name: "", functions: mir_program_function[](),
        body_positions: int[](), body_lines: int[](), binding_names: string[](),
        binding_values: int[](), instructions: mir_program_instruction[](),
        next_value: 0, expression_value: -1, expression_type: "", return_values: int[](),
        returned: false, function_index: 0, error: "",
    }
    state = native_parse_package(native_advance(state))
    for state.error == "" && state.lex.token != "" {
        if state.lex.token != "func" { state = native_fail(state, "unsupported top-level declaration: " + state.lex.token) }
        else { state = native_parse_signature(state) }
    }
    i := 0
    for state.error == "" && i < len(state.functions) {
        state = native_parse_body(state, i)
        i = i + 1
    }
    if state.error != "" {
        return mir_program_result {
            program: mir_program { package_name: state.package_name, entry_symbol: state.package_name + ".main", functions: mir_program_function[](), calls: mir_program_call[]() },
            error: state.error,
        }
    }
    return lower_mir_program(state.package_name, state.package_name + ".main", state.functions)
}
