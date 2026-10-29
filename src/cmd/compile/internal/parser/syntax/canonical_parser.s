package compile.internal.syntax
import (
    "compile.internal.ast"
    "std.option"
    "std.prelude"
)

extern "intrinsic" func __host_byte_at(string text, int index) int

// Canonical parsing owns source positions and produces the shared syntax AST.
// Value states make progress/error propagation explicit across recursive calls.
struct canonical_parser {
    string source
    int position
    int line
    int token_line
    string token
    string error
    expr expression
    pattern parsed_pattern
    stmt statement
    block_expr block
    enum_decl enumeration
    struct_decl structure
    function_decl function
    string text
    bool external_function
    string extern_library
    string receiver_name
    string receiver_type
    bool no_record
}

// Once a result is stored by its caller, keep only the parsing cursor. Carrying
// old ASTs through token advances repeatedly copies whole consumed subtrees.
func canonical_cursor(canonical_parser state) canonical_parser {
    return canonical_parser {
        source: state.source, position: state.position, line: state.line,
        token_line: state.token_line, token: state.token, error: state.error,
        text: state.text, external_function: state.external_function,
        extern_library: state.extern_library, receiver_name: state.receiver_name,
        receiver_type: state.receiver_type, no_record: state.no_record
    }
}

func canonical_char(string source, int index) string {
    if index < 0 || index >= len(source) { return "" }
    return std.prelude.char_at(source, index)
}

func canonical_ident_start(string ch) bool {
    return ch == "_" || (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z")
}

func canonical_ident(string text) bool {
    if text == "" || !canonical_ident_start(canonical_char(text, 0)) { return false }
    i := 1
    for i < len(text) {
        ch := canonical_char(text, i)
        if !canonical_ident_start(ch) && !(ch >= "0" && ch <= "9") { return false }
        i = i + 1
    }
    return true
}

func canonical_fail(canonical_parser initial, string message) canonical_parser {
    state := initial
    if state.error == "" { state.error = message }
    return state
}

func canonical_advance(canonical_parser initial) canonical_parser {
    state := initial
    if state.error != "" { return state }
    n := len(state.source)
    ignored := true
    for ignored && state.position < n {
        ignored = false
        ch := canonical_char(state.source, state.position)
        if ch == " " || ch == "\t" || ch == "\r" || ch == "\n" {
            if ch == "\n" { state.line = state.line + 1 }
            state.position = state.position + 1
            ignored = true
        } else if ch == "/" && canonical_char(state.source, state.position + 1) == "/" {
            for state.position < n && canonical_char(state.source, state.position) != "\n" { state.position = state.position + 1 }
            ignored = true
        } else if ch == "/" && canonical_char(state.source, state.position + 1) == "*" {
            state.position = state.position + 2
            depth := 1
            for state.position < n && depth > 0 {
                a := canonical_char(state.source, state.position)
                b := canonical_char(state.source, state.position + 1)
                if a == "/" && b == "*" { depth = depth + 1; state.position = state.position + 2 }
                else if a == "*" && b == "/" { depth = depth - 1; state.position = state.position + 2 }
                else {
                    if a == "\n" { state.line = state.line + 1 }
                    state.position = state.position + 1
                }
            }
            if depth != 0 { return canonical_fail(state, "unterminated block comment") }
            ignored = true
        }
    }
    state.token_line = state.line
    state.token = ""
    if state.position >= n { return state }
    start := state.position
    ch := canonical_char(state.source, start)
    if canonical_ident_start(ch) || (ch >= "0" && ch <= "9") {
        state.position = state.position + 1
        for state.position < n {
            next := canonical_char(state.source, state.position)
            if !canonical_ident_start(next) && !(next >= "0" && next <= "9") { break }
            state.position = state.position + 1
        }
    } else if ch == "\"" || ch == "'" {
        quote := ch
        state.position = state.position + 1
        closed := false
        for state.position < n {
            current := canonical_char(state.source, state.position)
            if current == quote { state.position = state.position + 1; closed = true; break }
            if current == "\n" { state.line = state.line + 1 }
            if current == "\\" { state.position = state.position + 1 }
            state.position = state.position + 1
        }
        if !closed { return canonical_fail(state, "unterminated quoted literal") }
    } else {
        state.position = state.position + 1
        pair := ch + canonical_char(state.source, state.position)
        if pair == "+=" || pair == "-=" || pair == "*=" || pair == "/=" || pair == "%=" || pair == "&=" || pair == "|=" || pair == "^=" || pair == "++" || pair == "--" || pair == ":=" || pair == "==" || pair == "!=" || pair == "<=" || pair == ">=" || pair == "&&" || pair == "||" || pair == "<<" || pair == ">>" || pair == "::" {
            state.position = state.position + 1
        } else if ch != "(" && ch != ")" && ch != "{" && ch != "}" && ch != "[" && ch != "]" && ch != "," && ch != ";" && ch != "." && ch != ":" && ch != "+" && ch != "-" && ch != "*" && ch != "/" && ch != "%" && ch != "=" && ch != "!" && ch != "&" && ch != "|" && ch != "^" && ch != "<" && ch != ">" {
            return canonical_fail(state, "illegal character: " + ch)
        }
    }
    state.token = std.prelude.prelude_slice(state.source, start, state.position)
    return state
}

func canonical_expect(canonical_parser initial, string token) canonical_parser {
    state := initial
    if state.error != "" { return state }
    if state.token != token { return canonical_fail(state, "expected '" + token + "', found '" + state.token + "'") }
    return canonical_advance(state)
}

func canonical_separators(canonical_parser initial) canonical_parser {
    state := initial
    for state.error == "" && (state.token == ";" || state.token == ",") { state = canonical_advance(state) }
    return state
}

func canonical_path(canonical_parser initial) canonical_parser {
    state := initial
    if !canonical_ident(state.token) { return canonical_fail(state, "expected identifier") }
    path := state.token
    state = canonical_advance(state)
    for state.error == "" && state.token == "." {
        state = canonical_advance(state)
        if !canonical_ident(state.token) { return canonical_fail(state, "expected path component") }
        path = path + "." + state.token
        state = canonical_advance(state)
    }
    state.text = path
    return state
}

func canonical_parse_type(canonical_parser initial) canonical_parser {
    state := initial
    prefix := ""
    if state.token == "&" || state.token == "*" {
        prefix = state.token
        state = canonical_advance(state)
        if state.token == "mut" { prefix = prefix + "mut "; state = canonical_advance(state) }
    }
    text := ""
    if state.token == "(" {
        state = canonical_advance(state)
        text = "("
        count := 0
        for state.error == "" && state.token != ")" {
            if count > 0 { state = canonical_expect(state, ","); text = text + "," }
            state = canonical_parse_type(state)
            text = text + state.text
            count = count + 1
        }
        state = canonical_expect(state, ")")
        text = text + ")"
    } else {
        state = canonical_path(state)
        text = state.text
    }
    for state.error == "" && (state.token == "[" || state.token == "*") {
        if state.token == "*" { text = text + "*"; state = canonical_advance(state); continue }
        state = canonical_advance(state)
        text = text + "["
        count := 0
        for state.error == "" && state.token != "]" {
            if count > 0 {
                state = canonical_expect(state, ",")
                text = text + ","
                if state.token == "]" { break }
            }
            if canonical_char(state.token, 0) >= "0" && canonical_char(state.token, 0) <= "9" {
                i := 0
                for i < len(state.token) {
                    ch := canonical_char(state.token, i)
                    if ch < "0" || ch > "9" { return canonical_fail(state, "expected decimal array length") }
                    i = i + 1
                }
                text = text + state.token
                state = canonical_advance(state)
            } else {
                state = canonical_parse_type(state)
                text = text + state.text
            }
            count = count + 1
        }
        state = canonical_expect(state, "]")
        text = text + "]"
    }
    state.text = prefix + text
    return state
}

func canonical_precedence(string token) int {
    if token == "||" { return 1 }
    if token == "&&" { return 2 }
    if token == "|" { return 3 }
    if token == "^" { return 4 }
    if token == "&" { return 5 }
    if token == "==" || token == "!=" { return 6 }
    if token == "<" || token == "<=" || token == ">" || token == ">=" { return 7 }
    if token == "<<" || token == ">>" { return 8 }
    if token == "+" || token == "-" { return 10 }
    if token == "*" || token == "/" || token == "%" { return 20 }
    return 0
}

func canonical_string(canonical_parser initial) canonical_parser {
    state := initial
    text := ""
    i := 1
    for i < len(state.token) - 1 {
        ch := canonical_char(state.token, i)
        if ch == "\\" {
            i = i + 1
            ch = canonical_char(state.token, i)
            if ch == "n" { ch = "\n" }
            else if ch == "r" { ch = "\r" }
            else if ch == "t" { ch = "\t" }
            else if ch != "\\" && ch != "\"" && ch != "'" { return canonical_fail(state, "unsupported string escape") }
        }
        text = text + ch
        i = i + 1
    }
    state = canonical_advance(state)
    state.expression = expr.string(compile.internal.ast.string_expr { value: text, inferred_type: option.none })
    return state
}

func canonical_expression_path(expr value) string {
    switch value {
        expr.name(name): { return name.name }
        expr.member(member): {
            root := canonical_expression_path(member.target.value)
            if root == "" { return "" }
            return root + "." + member.member
        }
        expr.index(index): {
            root := canonical_expression_path(index.target.value)
            argument := canonical_expression_path(index.index.value)
            if root == "" || argument == "" { return "" }
            return root + "[" + argument + "]"
        }
        _ : { return "" },
    }
}

func canonical_array(canonical_parser initial, option[string] type_text, string closing) canonical_parser {
    state := canonical_advance(initial)
    values := compile.internal.ast.expr[]()
    saved := state.no_record
    state.no_record = false
    for state.error == "" && state.token != closing {
        state = canonical_expression(state, 1)
        if state.error != "" { return state }
        values.push(state.expression)
        if state.token != closing { state = canonical_expect(state, ",") }
    }
    state = canonical_expect(state, closing)
    state.no_record = saved
    state.expression = expr.array(compile.internal.ast.array_literal { type_text: type_text, items: values })
    return state
}

func canonical_record(canonical_parser initial, string type_name) canonical_parser {
    state := canonical_expect(initial, "{")
    names := string[]()
    values := compile.internal.ast.expr[]()
    for state.error == "" && state.token != "}" {
        if !canonical_ident(state.token) { return canonical_fail(state, "expected record field name") }
        name := state.token
        state = canonical_advance(state)
        if state.token == ":" { state = canonical_advance(state) }
        state = canonical_expression(state, 1)
        if state.error != "" { return state }
        names.push(name)
        values.push(state.expression)
        if state.token != "}" { state = canonical_expect(state, ",") }
    }
    state = canonical_expect(state, "}")
    state.expression = expr.record(compile.internal.ast.record_literal { type_name: type_name, field_names: names, field_values: values, inferred_type: option.none })
    return state
}

func canonical_condition(canonical_parser initial) canonical_parser {
    state := initial
    saved := state.no_record
    state.no_record = true
    state = canonical_expression(state, 1)
    state.no_record = saved
    return state
}

func canonical_if(canonical_parser initial) canonical_parser {
    state := canonical_condition(canonical_advance(initial))
    if state.error != "" { return state }
    condition := state.expression
    state = canonical_block(state)
    then_branch := state.block
    otherwise := option[box[expr]].none
    if state.token == "else" {
        state = canonical_advance(state)
        if state.token == "if" { state = canonical_if(state) }
        else {
            state = canonical_block(state)
            state.expression = expr.block(state.block)
        }
        otherwise = option.some(std.prelude.box(state.expression))
    }
    state.expression = expr.if(compile.internal.ast.if_expr { condition: std.prelude.box(condition), then_branch: then_branch, else_branch: otherwise, inferred_type: option.none })
    return state
}

func canonical_loop_statement(canonical_parser initial) canonical_parser {
    state := canonical_expression_list(initial)
    if state.error != "" { return state }
    left := state.expression
    if canonical_assignment_operator(state.token) || state.token == "++" || state.token == "--" {
        return canonical_assignment(state, left, true)
    }
    state.statement = stmt.expr(compile.internal.ast.expr_stmt { expr: left })
    return state
}

func canonical_loop(canonical_parser initial) canonical_parser {
    state := initial
    kind := state.token
    state = canonical_advance(state)
    condition := option[box[expr]].none
    init := option[box[stmt]].none
    post := option[box[stmt]].none
    saved := state.no_record
    state.no_record = true
    clauses := false
    if kind == "for" && state.token == ";" {
        clauses = true
        state = canonical_advance(state)
    } else if state.token != "{" {
        state = canonical_expression_list(state)
        if state.error != "" { return state }
        first := state.expression
        if kind == "for" && (state.token == ";" || canonical_assignment_operator(state.token)) {
            clauses = true
            if state.token == ";" { state.statement = stmt.expr(compile.internal.ast.expr_stmt { expr: first }) }
            else { state = canonical_assignment(state, first, true) }
            if state.error != "" { return state }
            init = option.some(std.prelude.box(state.statement))
            state = canonical_expect(state, ";")
        } else { condition = option.some(std.prelude.box(first)) }
    }
    if clauses {
        if state.token != ";" {
            state = canonical_expression(state, 1)
            condition = option.some(std.prelude.box(state.expression))
        }
        state = canonical_expect(state, ";")
        if state.error != "" { return state }
        if state.token != "{" {
            state = canonical_loop_statement(state)
            post = option.some(std.prelude.box(state.statement))
        }
    }
    if state.error != "" { return state }
    state.no_record = saved
    state = canonical_block(state)
    if kind == "while" {
        if condition.is_none() { return canonical_fail(state, "while requires a condition") }
        state.expression = expr.while(compile.internal.ast.while_expr { condition: condition.unwrap(), body: state.block, inferred_type: option.none })
    } else {
        state.expression = expr.for(compile.internal.ast.for_expr { init: init, condition: condition, post: post, names: string[](), iterable: option.none, body: state.block, inferred_type: option.none })
    }
    return state
}

func canonical_pattern(canonical_parser initial) canonical_parser {
    state := initial
    if state.token == "_" {
        state = canonical_advance(state)
        state.parsed_pattern = pattern.wildcard(compile.internal.ast.wildcard_pattern {})
        return state
    }
    if state.token == "-" {
        state = canonical_advance(state)
        if state.token == "" { return canonical_fail(state, "expected negative integer pattern") }
        i := 0
        for i < len(state.token) {
            ch := canonical_char(state.token, i)
            if ch < "0" || ch > "9" { return canonical_fail(state, "expected negative integer pattern") }
            i = i + 1
        }
        text := "-" + state.token
        state = canonical_advance(state)
        state.parsed_pattern = pattern.literal(compile.internal.ast.literal_pattern { value: expr.int(compile.internal.ast.int_expr { value: text, inferred_type: option.none }) })
        return state
    }
    first := canonical_char(state.token, 0)
    if state.token == "true" || state.token == "false" || first == "\"" || first == "'" || (first >= "0" && first <= "9") {
        state = canonical_expression(state, 30)
        state.parsed_pattern = pattern.literal(compile.internal.ast.literal_pattern { value: state.expression })
        return state
    }
    if !canonical_ident(state.token) { return canonical_fail(state, "expected switch pattern") }
    path := state.token
    qualified := false
    state = canonical_advance(state)
    for state.error == "" && (state.token == "." || state.token == "::") {
        state = canonical_advance(state)
        if !canonical_ident(state.token) { return canonical_fail(state, "expected variant name") }
        path = path + "." + state.token
        qualified = true
        state = canonical_advance(state)
    }
    arguments := compile.internal.ast.pattern[]()
    if state.token == "(" {
        qualified = true
        state = canonical_advance(state)
        for state.error == "" && state.token != ")" {
            state = canonical_pattern(state)
            if state.error != "" { return state }
            arguments.push(state.parsed_pattern)
            if state.token != ")" { state = canonical_expect(state, ",") }
        }
        state = canonical_expect(state, ")")
    }
    if qualified { state.parsed_pattern = pattern.variant(compile.internal.ast.variant_pattern { path: path, args: arguments }) }
    else { state.parsed_pattern = pattern.name(compile.internal.ast.name_pattern { name: path }) }
    return state
}

// Go-style case bodies contain statements until the next labelled arm.
func canonical_case_body(canonical_parser initial) canonical_parser {
    state := initial
    statements := compile.internal.ast.stmt[]()
    final := option[expr].none
    for state.error == "" && state.token != "case" && state.token != "default" && state.token != "}" && state.token != "" {
        if state.token == ";" { state = canonical_advance(state); continue }
        if state.token == "continue" {
            statements.push(stmt.continue(compile.internal.ast.continue_stmt {}))
            state = canonical_advance(state)
        } else if state.token == "break" {
            statements.push(stmt.break(compile.internal.ast.break_stmt {}))
            state = canonical_advance(state)
        } else if state.token == "return" {
            line := state.token_line
            state = canonical_advance(state)
            value := option[expr].none
            if state.token != ";" && state.token != "}" && state.token != "case" && state.token != "default" && state.token_line == line {
                state = canonical_expression_list(state)
                value = option.some(state.expression)
            }
            statements.push(stmt.return(compile.internal.ast.return_stmt { value: value }))
        } else {
            // A statement-leading if ends at its own closing branch. Its
            // following unary expression is not an infix continuation.
            if state.token == "if" {
                state = canonical_if(state)
                state.statement = stmt.expr(compile.internal.ast.expr_stmt { expr: state.expression })
            } else { state = canonical_loop_statement(state) }
            if state.error != "" { return state }
            if state.token == "case" || state.token == "default" || state.token == "}" {
                switch state.statement {
                    stmt.expr(value): final = option.some(value.expr),
                    _ : statements.push(state.statement),
                }
            } else { statements.push(state.statement) }
        }
        state = canonical_cursor(state)
        if state.token == ";" { state = canonical_advance(state) }
    }
    state.block = compile.internal.ast.block_expr { statements: statements, final_expr: final, inferred_type: option.none }
    return state
}

func canonical_switch(canonical_parser initial) canonical_parser {
    state := canonical_condition(canonical_advance(initial))
    if state.error != "" { return state }
    subject := state.expression
    state = canonical_expect(state, "{")
    arms := compile.internal.ast.switch_arm[]()
    for state.error == "" && state.token != "}" {
        state = canonical_separators(state)
        if state.token == "}" { break }
        legacy := state.token == "case" || state.token == "default"
        if state.token == "default" {
            state.parsed_pattern = pattern.wildcard(compile.internal.ast.wildcard_pattern {})
            state = canonical_advance(state)
        } else {
            if state.token == "case" { state = canonical_advance(state) }
            state = canonical_pattern(state)
        }
        arm_pattern := state.parsed_pattern
        state = canonical_expect(state, ":")
        arm_line := state.token_line
        arm_value := expr.name(compile.internal.ast.name_expr { name: "()", inferred_type: option.none })
        if !legacy && state.token == "continue" {
            state = canonical_advance(state)
            jump := stmt.continue(compile.internal.ast.continue_stmt {})
            arm_value = expr.block(compile.internal.ast.block_expr { statements: [jump], final_expr: option.none, inferred_type: option.none })
        } else if !legacy && state.token == "break" {
            state = canonical_advance(state)
            jump := stmt.break(compile.internal.ast.break_stmt {})
            arm_value = expr.block(compile.internal.ast.block_expr { statements: [jump], final_expr: option.none, inferred_type: option.none })
        } else if legacy {
            state = canonical_case_body(state)
            arm_value = expr.block(state.block)
        } else if state.token == "return" {
            state = canonical_advance(state)
            returned := option[expr].none
            if state.token != "," && state.token != "}" && state.token != ";" && state.token_line == arm_line {
                state = canonical_expression(state, 1)
                returned = option.some(state.expression)
            }
            statement := stmt.return(compile.internal.ast.return_stmt { value: returned })
            arm_value = expr.block(compile.internal.ast.block_expr { statements: [statement], final_expr: option.none, inferred_type: option.none })
        } else {
            state = canonical_expression(state, 1)
            arm_value = state.expression
            if canonical_assignment_operator(state.token) || state.token == "++" || state.token == "--" {
                state = canonical_assignment(state, arm_value, false)
                statement := state.statement
                arm_value = expr.block(compile.internal.ast.block_expr { statements: [statement], final_expr: option.none, inferred_type: option.none })
            }
        }
        if state.error != "" { return state }
        arms.push(compile.internal.ast.switch_arm { pattern: arm_pattern, expr: arm_value })
        if state.token == "," || state.token == ";" { state = canonical_advance(state) }
        else if !legacy && state.token != "}" && state.token_line <= arm_line { return canonical_fail(state, "expected switch arm separator") }
    }
    state = canonical_expect(state, "}")
    state.expression = expr.switch(compile.internal.ast.switch_expr { subject: std.prelude.box(subject), arms: arms, inferred_type: option.none })
    return state
}

func canonical_expression(canonical_parser initial, int minimum) canonical_parser {
    state := initial
    if state.error != "" { return state }
    value := expr.name(compile.internal.ast.name_expr { name: "()", inferred_type: option.some("()") })
    token := state.token
    if token == "[" {
        probe := canonical_advance(state)
        if probe.token == "]" {
            state = canonical_parse_type(canonical_advance(probe))
            type_text := "[]" + state.text
            if state.token != "{" && state.token != "(" {
                state.expression = expr.name(compile.internal.ast.name_expr { name: type_text, inferred_type: option.none })
            } else {
                closing := "}"
                if state.token == "(" { closing = ")" }
                state = canonical_array(state, option.some(type_text), closing)
            }
        } else { state = canonical_array(state, option.none, "]") }
        value = state.expression
    } else if token == "switch" { state = canonical_switch(state); value = state.expression }
    else if token == "if" { state = canonical_if(state); value = state.expression }
    else if token == "while" || token == "for" { state = canonical_loop(state); value = state.expression }
    else if token == "{" {
        state = canonical_block(state)
        value = expr.block(state.block)
    } else if canonical_char(token, 0) == "\"" || canonical_char(token, 0) == "'" {
        state = canonical_string(state)
        value = state.expression
    } else if token == "&" {
        state = canonical_advance(state)
        mutable := false
        if state.token == "mut" { mutable = true; state = canonical_advance(state) }
        state = canonical_expression(state, 30)
        value = expr.borrow(compile.internal.ast.borrow_expr { target: std.prelude.box(state.expression), mutable: mutable, inferred_type: option.none })
    } else if token == "!" {
        state = canonical_expression(canonical_advance(state), 30)
        value = expr.binary(compile.internal.ast.binary_expr { left: std.prelude.box(state.expression), op: "==", right: std.prelude.box(expr.bool(compile.internal.ast.bool_expr { value: false, inferred_type: option.none })), inferred_type: option.none })
    } else if token == "-" || token == "+" {
        state = canonical_expression(canonical_advance(state), 30)
        value = state.expression
        if token == "-" { value = expr.binary(compile.internal.ast.binary_expr { left: std.prelude.box(expr.int(compile.internal.ast.int_expr { value: "0", inferred_type: option.none })), op: "-", right: std.prelude.box(value), inferred_type: option.none }) }
    } else if token == "(" {
        state = canonical_advance(state)
        saved := state.no_record
        state.no_record = false
        if state.token != ")" { state = canonical_expression_list(state); value = state.expression }
        state.no_record = saved
        state = canonical_expect(state, ")")
    } else if token == "true" || token == "false" {
        value = expr.bool(compile.internal.ast.bool_expr { value: token == "true", inferred_type: option.none })
        state = canonical_advance(state)
    } else if canonical_char(token, 0) >= "0" && canonical_char(token, 0) <= "9" {
        value = expr.int(compile.internal.ast.int_expr { value: token, inferred_type: option.none })
        state = canonical_advance(state)
    } else if canonical_ident(token) {
        value = expr.name(compile.internal.ast.name_expr { name: token, inferred_type: option.none })
        state = canonical_advance(state)
    } else {
        return canonical_fail(state, "expected expression, found '" + token + "'")
    }
    for state.error == "" {
        if state.token == "*" {
            probe := canonical_advance(state)
            if probe.token == ")" || probe.token == "," || probe.token == ";" || probe.token == "}" {
                value = expr.borrow(compile.internal.ast.borrow_expr { target: std.prelude.box(value), mutable: true, inferred_type: option.none })
                state = probe
            } else {
                precedence := canonical_precedence(state.token)
                if precedence < minimum { break }
                state = canonical_expression(probe, precedence + 1)
                value = expr.binary(compile.internal.ast.binary_expr { left: std.prelude.box(value), op: "*", right: std.prelude.box(state.expression), inferred_type: option.none })
            }
        } else if state.token == "{" && !state.no_record && canonical_expression_path(value) != "" {
            state = canonical_record(state, canonical_expression_path(value))
            value = state.expression
        } else if state.token == "." || state.token == "::" {
            state = canonical_advance(state)
            if !canonical_ident(state.token) { return canonical_fail(state, "expected member name") }
            value = expr.member(compile.internal.ast.member_expr { target: std.prelude.box(value), member: state.token, inferred_type: option.none })
            state = canonical_advance(state)
        } else if state.token == "[" {
            target := value
            state = canonical_advance(state)
            if state.token == "]" {
                type_text := canonical_expression_path(target)
                if type_text == "" { return canonical_fail(state, "empty index requires an array type") }
                type_text = type_text + "[]"
                state = canonical_advance(state)
                for state.error == "" && state.token == "[" {
                    state = canonical_expect(canonical_advance(state), "]")
                    type_text = type_text + "[]"
                }
                if state.token != "{" && state.token != "(" {
                    value = expr.name(compile.internal.ast.name_expr { name: type_text, inferred_type: option.none })
                } else {
                    closing := "}"
                    if state.token == "(" { closing = ")" }
                    state = canonical_array(state, option.some(type_text), closing)
                    value = state.expression
                }
            } else {
                state = canonical_expression(state, 1)
                index := state.expression
                state = canonical_expect(state, "]")
                value = expr.index(compile.internal.ast.index_expr { target: std.prelude.box(target), index: std.prelude.box(index), inferred_type: option.none })
            }
        } else if state.token == "(" {
            args := compile.internal.ast.expr[]()
            saved := state.no_record
            state.no_record = false
            state = canonical_advance(state)
            for state.error == "" && state.token != ")" {
                if len(args) > 0 { state = canonical_expect(state, ",") }
                state = canonical_expression(state, 1)
                if state.error != "" { return state }
                args.push(state.expression)
                if state.token == "" { return canonical_fail(state, "unterminated call") }
            }
            state = canonical_expect(state, ")")
            state.no_record = saved
            value = expr.call(compile.internal.ast.call_expr { callee: std.prelude.box(value), args: args, inferred_type: option.none, resolved_callee: option.none, type_args: string[]() })
        } else if state.token == "as" {
            state = canonical_parse_type(canonical_advance(state))
            if state.error != "" { return state }
            target := expr.name(compile.internal.ast.name_expr { name: state.text, inferred_type: option.none })
            value = expr.call(compile.internal.ast.call_expr { callee: std.prelude.box(target), args: [value], inferred_type: option.none, resolved_callee: option.none, type_args: string[]() })
        } else {
            precedence := canonical_precedence(state.token)
            if precedence < minimum { break }
            operator := state.token
            state = canonical_expression(canonical_advance(state), precedence + 1)
            value = expr.binary(compile.internal.ast.binary_expr { left: std.prelude.box(value), op: operator, right: std.prelude.box(state.expression), inferred_type: option.none })
        }
    }
    state.expression = value
    return state
}

func canonical_var_binding(canonical_parser initial) bool {
    if initial.token != "var" { return false }
    state := canonical_advance(canonical_cursor(initial))
    if !canonical_ident(state.token) { return false }
    state = canonical_advance(state)
    return state.token == "="
}

func canonical_block(canonical_parser initial) canonical_parser {
    state := canonical_expect(initial, "{")
    statements := compile.internal.ast.stmt[]()
    final := option[expr].none
    for state.error == "" && state.token != "}" && state.token != "" {
        if state.token == ";" { state = canonical_advance(state); continue }
        if state.token == "continue" {
            statements.push(stmt.continue(compile.internal.ast.continue_stmt {}))
            state = canonical_advance(state)
        } else if state.token == "break" {
            statements.push(stmt.break(compile.internal.ast.break_stmt {}))
            state = canonical_advance(state)
        } else if canonical_var_binding(state) {
            state = canonical_advance(state)
            name := state.token
            state = canonical_expect(canonical_advance(state), "=")
            state = canonical_expression(state, 1)
            statements.push(stmt.let(compile.internal.ast.var_stmt { name: name, type_name: option.none, value: state.expression }))
        } else if state.token == "return" {
            return_line := state.token_line
            state = canonical_advance(state)
            value := option[expr].none
            if state.token != ";" && state.token != "}" && state.token_line == return_line {
                state = canonical_expression_list(state)
                value = option.some(state.expression)
            }
            statements.push(stmt.return(compile.internal.ast.return_stmt { value: value }))
        } else {
            // Keep statement boundaries without restricting multiline binary
            // operators in bindings, returns or parenthesized expressions.
            if state.token == "if" { state = canonical_if(state) }
            else { state = canonical_expression_list(state) }
            left := state.expression
            if canonical_assignment_operator(state.token) || state.token == "++" || state.token == "--" {
                state = canonical_assignment(state, left, true)
                statements.push(state.statement)
            } else if state.token == "}" {
                final = option.some(left)
            } else {
                statements.push(stmt.expr(compile.internal.ast.expr_stmt { expr: left }))
            }
        }
        state = canonical_cursor(state)
        if state.token == ";" { state = canonical_advance(state) }
    }
    state = canonical_expect(state, "}")
    state = canonical_cursor(state)
    state.block = compile.internal.ast.block_expr { statements: statements, final_expr: final, inferred_type: option.none }
    return state
}

func canonical_function(canonical_parser initial) canonical_parser {
    state := canonical_advance(initial)
    state.receiver_name = ""
    state.receiver_type = ""
    if state.token == "(" {
        state = canonical_parse_type(canonical_advance(state))
        state.receiver_type = state.text
        if !canonical_ident(state.token) { return canonical_fail(state, "expected receiver name") }
        state.receiver_name = state.token
        state = canonical_expect(canonical_advance(state), ")")
    }
    if !canonical_ident(state.token) { return canonical_fail(state, "expected function name") }
    name := state.token
    state = canonical_advance(state)
    generics := string[]()
    if state.token == "[" {
        state = canonical_advance(state)
        for state.error == "" && state.token != "]" {
            if len(generics) > 0 { state = canonical_expect(state, ",") }
            if !canonical_ident(state.token) { return canonical_fail(state, "expected generic parameter") }
            generics.push(state.token)
            state = canonical_advance(state)
        }
        state = canonical_expect(state, "]")
    }
    state = canonical_expect(state, "(")
    params := compile.internal.ast.param[]()
    for state.error == "" && state.token != ")" {
        if len(params) > 0 { state = canonical_expect(state, ","); if state.token == ")" { break } }
        first := state.token
        state = canonical_parse_type(state)
        type_name := state.text
        if !canonical_ident(state.token) { return canonical_fail(state, "expected parameter name") }
        parameter_name := state.token
        probe := canonical_advance(state)
        if type_name == first + "*" && (probe.token == "." || probe.token == "[") {
            state = canonical_parse_type(state)
            type_name = state.text + "*"
            parameter_name = first
        } else { state = probe }
        params.push(compile.internal.ast.param { name: parameter_name, type_name: type_name })
    }
    signature_line := state.token_line
    state = canonical_expect(state, ")")
    returns := option[string].none
    if state.token != "{" && state.token != ";" && state.token != "" && (state.token_line == signature_line || !state.external_function) { state = canonical_parse_type(state); returns = option.some(state.text) }
    body := option[block_expr].none
    if state.external_function {
        if state.token == "{" { return canonical_fail(state, "external function cannot have a body") }
    } else {
        state = canonical_block(state)
        body = option.some(state.block)
    }
    state = canonical_cursor(state)
    state.function = compile.internal.ast.function_decl { sig: compile.internal.ast.function_sig { name: name, generics: generics, params: params, return_type: returns }, body: body, is_public: false, extern_library: state.extern_library }
    state.external_function = false
    state.extern_library = ""
    return state
}

func canonical_enum(canonical_parser initial) canonical_parser {
    state := canonical_advance(initial)
    if !canonical_ident(state.token) { return canonical_fail(state, "expected enum name") }
    name := state.token
    state = canonical_advance(state)
    generics := string[]()
    if state.token == "[" {
        state = canonical_advance(state)
        for state.error == "" && state.token != "]" {
            if len(generics) > 0 { state = canonical_expect(state, ",") }
            if !canonical_ident(state.token) { return canonical_fail(state, "expected enum type parameter") }
            generics.push(state.token)
            state = canonical_advance(state)
        }
        state = canonical_expect(state, "]")
    }
    state = canonical_expect(state, "{")
    variants := compile.internal.ast.enum_variant[]()
    for state.error == "" && state.token != "}" {
        if !canonical_ident(state.token) { return canonical_fail(state, "expected enum variant") }
        variant_name := state.token
        state = canonical_advance(state)
        payload := option[string].none
        if state.token == "(" {
            state = canonical_parse_type(canonical_advance(state))
            payload = option.some(state.text)
            state = canonical_expect(state, ")")
        }
        explicit := false
        tag := 0
        if state.token == "=" {
            explicit = true
            state = canonical_advance(state)
            sign := 1
            if state.token == "-" { sign = -1; state = canonical_advance(state) }
            if state.token == "" { return canonical_fail(state, "missing enum discriminant") }
            i := 0
            for i < len(state.token) {
                ch := canonical_char(state.token, i)
                if ch < "0" || ch > "9" { return canonical_fail(state, "enum discriminant requires a decimal integer") }
                digit := __host_byte_at(ch, 0) - 48
                if tag > 461168601842738790 || (tag == 461168601842738790 && digit > 3) { return canonical_fail(state, "enum discriminant overflow") }
                tag = tag * 10 + digit
                i = i + 1
            }
            tag = tag * sign
            state = canonical_advance(state)
        }
        variants.push(compile.internal.ast.enum_variant { name: variant_name, payload: payload, explicit_value: tag, has_explicit_value: explicit })
        if state.token != "}" { state = canonical_expect(state, ",") }
    }
    state = canonical_expect(state, "}")
    state.enumeration = compile.internal.ast.enum_decl { name: name, generics: generics, variants: variants, is_public: false }
    return state
}

// Match the seed grammar's legacy name-first field recognition. Compound and
// qualified types remain type-first; `name: Type` is always unambiguous.
func canonical_likely_type_start(string token) bool {
    if token == "string" || token == "int" || token == "bool" || token == "float" || token == "option" || token == "array" || token == "map" { return true }
    if token == "expr" || token == "pattern" || token == "field" || token == "param" || token == "stmt" || token == "decl" || token == "type" || token == "token" || token == "lexer" || token == "parser" || token == "node" || token == "block" || token == "scope" || token == "table" { return true }
    i := 0
    for i < len(token) {
        if canonical_char(token, i) == "_" { return true }
        i = i + 1
    }
    return false
}

func canonical_struct(canonical_parser initial) canonical_parser {
    state := canonical_advance(initial)
    if !canonical_ident(state.token) { return canonical_fail(state, "expected struct name") }
    name := state.token
    state = canonical_advance(state)
    generics := string[]()
    if state.token == "[" {
        state = canonical_advance(state)
        for state.error == "" && state.token != "]" {
            if len(generics) > 0 { state = canonical_expect(state, ",") }
            if !canonical_ident(state.token) { return canonical_fail(state, "expected struct type parameter") }
            generics.push(state.token)
            state = canonical_advance(state)
        }
        state = canonical_expect(state, "]")
    }
    state = canonical_expect(state, "{")
    fields := compile.internal.ast.field[]()
    for state.error == "" && state.token != "}" {
        state = canonical_separators(state)
        if state.token == "}" { break }
        public := false
        if state.token == "pub" { public = true; state = canonical_advance(state) }
        first := state.token
        state = canonical_parse_type(state)
        if state.error != "" { return state }
        type_name := state.text
        field_name := ""
        if state.token == ":" {
            field_name = type_name
            if !canonical_ident(field_name) { return canonical_fail(state, "expected field name") }
            state = canonical_parse_type(canonical_advance(state))
            type_name = state.text
        } else if type_name == first && canonical_ident(first) && (first == "sig" || (!canonical_likely_type_start(first) && canonical_likely_type_start(state.token))) {
            field_name = first
            state = canonical_parse_type(state)
            type_name = state.text
        } else {
            if !canonical_ident(state.token) { return canonical_fail(state, "expected field name") }
            probe := canonical_advance(state)
            if type_name == first + "*" && (probe.token == "." || probe.token == "[") {
                field_name = first
                state = canonical_parse_type(state)
                type_name = state.text + "*"
            } else { field_name = state.token; state = probe }
        }
        fields.push(compile.internal.ast.field { name: field_name, type_name: type_name, is_public: public })
    }
    state = canonical_expect(state, "}")
    state.structure = compile.internal.ast.struct_decl { name: name, generics: generics, fields: fields, is_public: false }
    return state
}

func canonical_parse(string source) (source_file, syntax_error) {
    state := canonical_advance(canonical_parser { source: source, position: 0, line: 1, token_line: 1, token: "", error: "" })
    output := compile.internal.ast.source_file { pkg: "", uses: compile.internal.ast.use_decl[](), items: compile.internal.ast.item[](), item_packages: string[]() }
    package_name := ""
    public := false
    for state.error == "" && state.token != "" {
        if state.token == "pub" {
            if package_name == "" { state = canonical_fail(state, "expected package declaration") }
            public = true
            state = canonical_advance(state)
            if state.token != "struct" && state.token != "enum" && state.token != "func" && state.token != "extern" { state = canonical_fail(state, "pub requires a declaration") }
        }
        else if state.token == ";" { state = canonical_advance(state) }
        else if state.token == "package" {
            state = canonical_path(canonical_advance(state))
            package_name = state.text
            if output.pkg == "" { output.pkg = package_name }
        } else if package_name == "" { state = canonical_fail(state, "expected package declaration") }
        else if state.token == "import" || state.token == "use" {
            state = canonical_advance(state)
            group := state.token == "("
            if group { state = canonical_advance(state) }
            for state.error == "" {
                if group && state.token == ")" { state = canonical_advance(state); break }
                if state.token == ";" { state = canonical_advance(state); continue }
                path := state.token
                if canonical_char(path, 0) == "\"" {
                    path = std.prelude.prelude_slice(path, 1, len(path) - 1)
                    state = canonical_advance(state)
                } else { state = canonical_path(state); path = state.text }
                output.uses.push(compile.internal.ast.use_decl { path: path, alias: option.none })
                if !group { break }
            }
        } else if state.token == "extern" {
            state.external_function = true
            state = canonical_advance(state)
            if canonical_char(state.token, 0) == "\"" {
                state.extern_library = std.prelude.prelude_slice(state.token, 1, len(state.token) - 1)
                state = canonical_advance(state)
            }
            if state.token != "func" { state = canonical_fail(state, "extern requires a function declaration") }
        } else if state.token == "const" {
            state = canonical_advance(state)
            if !canonical_ident(state.token) { return syntax_error { message: "expected constant name", line: state.token_line, column: 1 } }
            name := state.token
            state = canonical_expect(canonical_advance(state), "=")
            state = canonical_expression(state, 1)
            output.items.push(item.const(compile.internal.ast.const_decl { name: name, value: option.some(state.expression), iota_index: 0 }))
            output.item_packages.push(package_name)
            public = false
        } else if state.token == "struct" {
            state = canonical_struct(state)
            state.structure.is_public = public
            public = false
            output.items.push(item.struct(state.structure))
            output.item_packages.push(package_name)
        } else if state.token == "enum" {
            state = canonical_enum(state)
            state.enumeration.is_public = public
            public = false
            output.items.push(item.enum(state.enumeration))
            output.item_packages.push(package_name)
        } else if state.token == "func" {
            state = canonical_function(state)
            state.function.is_public = public
            public = false
            if state.receiver_name == "" { output.items.push(item.function(state.function)) }
            else { output.items.push(item.method(compile.internal.ast.receiver_method_decl { receiver_name: state.receiver_name, receiver_type: state.receiver_type, method: state.function })) }
            output.item_packages.push(package_name)
        } else if canonical_ident(state.token) {
            name := state.token
            state = canonical_expect(canonical_advance(state), ":=")
            state = canonical_expression(state, 1)
            output.items.push(item.var(compile.internal.ast.var_decl { name: name, type_name: option.none, value: option.some(state.expression) }))
            output.item_packages.push(package_name)
            public = false
        } else { state = canonical_fail(state, "unsupported top-level declaration: " + state.token) }
        state = canonical_cursor(state)
    }
    if state.error != "" { return syntax_error { message: state.error, line: state.token_line, column: 1 } }
    if output.pkg == "" { return syntax_error { message: "expected package declaration", line: 1, column: 1 } }
    return output
}

func canonical_assignment_operator(string token) bool {
    return token == ":=" || token == "=" || token == "+=" || token == "-=" || token == "*=" || token == "/=" || token == "%=" || token == "&=" || token == "|=" || token == "^="
}

func canonical_assignment(canonical_parser initial, expr left, bool allow_tuple) canonical_parser {
    state := initial
    operator := state.token
    rhs := expr.int(compile.internal.ast.int_expr { value: "1", inferred_type: option.none })
    if operator == "++" || operator == "--" {
        if operator == "++" { operator = "+=" } else { operator = "-=" }
        state = canonical_advance(state)
    } else {
        state = canonical_advance(state)
        if allow_tuple { state = canonical_expression_list(state) } else { state = canonical_expression(state, 1) }
        rhs = state.expression
    }
    if state.error != "" { return state }
    switch left {
        expr.tuple(tuple): {
            if operator != "=" && operator != ":=" { return canonical_fail(state, "parallel assignment requires = or :=") }
            state.statement = stmt.multi(compile.internal.ast.multi_assign_stmt { targets: tuple.items, declaration: operator == ":=", value: rhs })
            return state
        }
        _: (),
    }
    name := ""
    switch left { expr.name(identifier): name = identifier.name, _ : (), }
    if name != "" {
        if name == "_" && (operator == "=" || operator == ":=") {
            state.statement = stmt.expr(compile.internal.ast.expr_stmt { expr: rhs })
            return state
        }
        if operator != "=" && operator != ":=" { rhs = expr.binary(compile.internal.ast.binary_expr { left: std.prelude.box(left), op: std.prelude.prelude_slice(operator, 0, len(operator) - 1), right: std.prelude.box(rhs), inferred_type: option.none }) }
        if operator == ":=" { state.statement = stmt.let(compile.internal.ast.var_stmt { name: name, type_name: option.none, value: rhs }) }
        else { state.statement = stmt.assign(compile.internal.ast.assign_stmt { name: name, value: rhs }) }
        return state
    }
    if operator == ":=" { return canonical_fail(state, "declaration requires a local name") }
    valid := false
    switch left { expr.member(_): valid = true, expr.index(_): valid = true, _ : (), }
    if !valid { return canonical_fail(state, "assignment requires a place") }
    state.statement = stmt.store(compile.internal.ast.store_stmt { target: left, op: operator, value: rhs })
    return state
}

func canonical_expression_list(canonical_parser initial) canonical_parser {
    state := canonical_expression(initial, 1)
    if state.error != "" || state.token != "," { return state }
    first := state.expression
    items := [first]
    for state.error == "" && state.token == "," {
        state = canonical_expression(canonical_advance(state), 1)
        items.push(state.expression)
    }
    state.expression = expr.tuple(compile.internal.ast.tuple_expr { items: items, inferred_type: option.none })
    return state
}
