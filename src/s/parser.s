package s
use std.option.option
use std.prelude.char_at
use std.prelude.len
use std.result.result
use std.vec.vec

struct parse_error {
    string message
    int line
    int column
}

struct parser {
    vec[token] tokens
    int index
}

func parse_source(string source) (source_file, parse_error) {
    switch new_lexer(source).tokenize() {
        tokens : parse_tokens(tokens),
        err : parse_error {
            message: err.message,
            line: err.line,
            column: err.column,
        },
    }
}

func parse_tokens(vec[token] tokens) (source_file, parse_error) {
    parser p := parser {
        tokens: tokens,
        index: 0,
    }
    p.parse_source_file()
}

int global_parse_depth = 0

func log_depth(string msg) {
    print(msg)
}

func (parser* self) parse_source_file() (source_file, parse_error) {
    global_parse_depth = global_parse_depth + 1
    log_depth("parse_source_file depth: " + to_string(global_parse_depth))
    
    _, err := self.expect_keyword("package")
    if err.message != "" {
        source_file empty
        return empty, err
    }
    
    pkg, err := self.parse_path()
    if err.message != "" {
        source_file empty
        return empty, err
    }
    
    vec[use_decl] uses = vec[use_decl]()
    vec[item] items = vec[item]()
    
    for self.at_keyword("use") {
        decl, err := self.parse_use_decl()
        if err.message != "" {
            source_file empty
            return empty, err
        }
        uses.push(decl)
    }
    
    for !self.at(token_kind::eof) {
        if self.at_keyword("const") && self.at_symbol_after_keyword("(") {
            consts, err := self.parse_const_group_items()
            if err.message != "" {
                source_file empty
                return empty, err
            }
            int ci = 0
            for ci < consts.len() {
                items.push(item::const(consts[ci]))
                ci = ci + 1
            }
            continue
        }
        item_val, err := self.parse_item()
        if err.message != "" {
            source_file empty
            return empty, err
        }
        items.push(item_val)
    }
    
    global_parse_depth = global_parse_depth - 1
    log_depth("parse_source_file exit depth: " + to_string(global_parse_depth))
    source_file {
        pkg: pkg,
        uses: uses,
        items: items,
    }
}

func (parser* self) parse_use_decl() (use_decl, parse_error) {
    _, err := self.expect_keyword("use")
    if err.message != "" {
        use_decl empty
        return empty, err
    }
    
    path, err := self.parse_use_path()
    if err.message != "" {
        use_decl empty
        return empty, err
    }
    
    option[string] alias = option::none
    if self.at_keyword("as") {
        _, err := self.advance()
        if err.message != "" {
            use_decl empty
            return empty, err
        }
        alias_val, err := self.expect_ident()
        if err.message != "" {
            use_decl empty
            return empty, err
        }
        alias = option::some(alias_val)
    }
    
    use_decl {
        path: path,
        alias: alias,
    }
}

func (parser* self) parse_item() (item, parse_error) {
    if self.at_keyword("func") {
        parsed, err := self.parse_function(true)
        if err.message != "" {
            item empty
            return empty, err
        }
        switch parsed.receiver {
            option::some(r) : {
                method := function_decl {
                    sig: parsed.sig,
                    body: parsed.body,
                    is_public: starts_with_upper(parsed.sig.name),
                }
                return item::method(receiver_method_decl {
                    receiver_name: r.name,
                    receiver_type: r.type_name,
                    method: method,
                }), parse_error{ message: "", line: 0, column: 0 }
            },
            option::none : {
                return item::function(parsed), parse_error{ message: "", line: 0, column: 0 }
            }
        }
    }
    if self.at_keyword("const") {
        decl, err := self.parse_const_decl()
        if err.message != "" {
            item empty
            return empty, err
        }
        return item::const(decl), parse_error{ message: "", line: 0, column: 0 }
    }
    if self.at_keyword("var") {
        decl, err := self.parse_var_decl()
        if err.message != "" {
            item empty
            return empty, err
        }
        return item::var(decl), parse_error{ message: "", line: 0, column: 0 }
    }
    if self.at_keyword("struct") {
        decl, err := self.parse_struct_decl()
        if err.message != "" {
            item empty
            return empty, err
        }
        return item::struct(decl), parse_error{ message: "", line: 0, column: 0 }
    }
    if self.at_keyword("enum") {
        decl, err := self.parse_enum_decl()
        if err.message != "" {
            item empty
            return empty, err
        }
        return item::enum(decl), parse_error{ message: "", line: 0, column: 0 }
    }
    if self.at_keyword("trait") {
        decl, err := self.parse_trait_decl()
        if err.message != "" {
            item empty
            return empty, err
        }
        return item::trait(decl), parse_error{ message: "", line: 0, column: 0 }
    }
    item empty
    return empty, self.error_here("unexpected token")
}

func (parser* self) parse_const_decl() (const_decl, parse_error) {
    _, err := self.expect_keyword("const")
    if err.message != "" {
        const_decl empty
        return empty, err
    }
    entry, err := self.parse_const_entry(false, 0)
    if err.message != "" {
        const_decl empty
        return empty, err
    }
    self.eat_symbol(";")
    entry
}

func (parser* self) parse_const_group_items() (vec[const_decl], parse_error) {
    _, err := self.expect_keyword("const")
    if err.message != "" {
        vec[const_decl] empty
        return empty, err
    }
    _, err = self.expect_symbol("(")
    if err.message != "" {
        vec[const_decl] empty
        return empty, err
    }
    vec[const_decl] out = vec[const_decl]()
    int iota_index = 0
    for !self.eat_symbol(")") {
        if self.eat_symbol(";") || self.eat_symbol(",") {
            continue
        }
        entry, err := self.parse_const_entry(true, iota_index)
        if err.message != "" {
            vec[const_decl] empty
            return empty, err
        }
        out.push(entry)
        iota_index = iota_index + 1
        self.eat_symbol(";")
        self.eat_symbol(",")
    }
    out
}

func (parser* self) parse_const_entry(bool allow_omitted_value, int iota_index) (const_decl, parse_error) {
    name, err := self.expect_ident()
    if err.message != "" {
        const_decl empty
        return empty, err
    }
    option[expr] value = option::none
    if self.eat_symbol("=") {
        val, err := self.parse_expr()
        if err.message != "" {
            const_decl empty
            return empty, err
        }
        value = option::some(val)
    } else if !allow_omitted_value {
        return self.error_here("expected symbol =")
    }
    const_decl {
        name: name,
        value: value,
        iota_index: iota_index,
    }
}

func (parser* self) parse_var_decl() (var_decl, parse_error) {
    _, err := self.expect_keyword("var")
    if err.message != "" {
        var_decl empty
        return empty, err
    }
    name, err := self.expect_ident()
    if err.message != "" {
        var_decl empty
        return empty, err
    }
    option[string] type_name = option::none
    option[expr] value = option::none
    if !self.at_symbol("=") && !self.at_symbol(";") {
        type_expr, err := self.parse_type_expr()
        if err.message != "" {
            var_decl empty
            return empty, err
        }
        type_name = option::some(type_expr)
    }
    if self.eat_symbol("=") {
        val, err := self.parse_expr()
        if err.message != "" {
            var_decl empty
            return empty, err
        }
        value = option::some(val)
    }
    self.eat_symbol(";")
    var_decl {
        name: name,
        type_name: type_name,
        value: value,
    }
}

func (parser* self) parse_function_decl() (function_decl, parse_error) {
    pair, err := self.parse_function(true)
    if err.message != "" {
        function_decl empty
        return empty, err
    }
    if pair.receiver.is_some() {
        return self.error_here("method receiver not allowed in this context")
    }
    function_decl {
        sig: pair.sig,
        body: pair.body,
        is_public: starts_with_upper(pair.sig.name),
    }
}

func (parser* self) parse_struct_decl() (struct_decl, parse_error) {
    _, err := self.expect_keyword("struct")
    if err.message != "" {
        struct_decl empty
        return empty, err
    }
    name, err := self.expect_ident()
    if err.message != "" {
        struct_decl empty
        return empty, err
    }
    generics, err := self.parse_generic_params()
    if err.message != "" {
        struct_decl empty
        return empty, err
    }
    _, err = self.expect_symbol("{")
    if err.message != "" {
        struct_decl empty
        return empty, err
    }
    vec[field] fields = vec[field]()
    for !self.eat_symbol("}") {
        f, err := self.parse_named_type(vec[string] { ",", "}" })
        if err.message != "" {
            struct_decl empty
            return empty, err
        }
        fields.push(field {
            name: f.name,
            type_name: f.type_name,
            is_public: starts_with_upper(f.name),
        })
        self.eat_symbol(",")
    }
    struct_decl {
        name: name,
        generics: generics,
        fields: fields,
        is_public: starts_with_upper(name),
    }
}

func (parser* self) parse_enum_decl() (enum_decl, parse_error) {
    _, err := self.expect_keyword("enum")
    if err.message != "" {
        enum_decl empty
        return empty, err
    }
    name, err := self.expect_ident()
    if err.message != "" {
        enum_decl empty
        return empty, err
    }
    generics, err := self.parse_generic_params()
    if err.message != "" {
        enum_decl empty
        return empty, err
    }
    _, err = self.expect_symbol("{")
    if err.message != "" {
        enum_decl empty
        return empty, err
    }
    vec[enum_variant] variants = vec[enum_variant]()
    for !self.eat_symbol("}") {
        variant_name, err := self.expect_ident()
        if err.message != "" {
            enum_decl empty
            return empty, err
        }
        option[string] payload = option::none
        if self.eat_symbol("(") {
            ty, err := self.parse_type_text(vec[string] { ")" })
            if err.message != "" {
                enum_decl empty
                return empty, err
            }
            _, err = self.expect_symbol(")")
            if err.message != "" {
                enum_decl empty
                return empty, err
            }
            payload = option::some(ty)
        }
        variants.push(enum_variant {
            name: variant_name,
            payload: payload,
        })
        self.eat_symbol(",")
    }
    enum_decl {
        name: name,
        generics: generics,
        variants: variants,
        is_public: starts_with_upper(name),
    }
}

func (parser* self) parse_trait_decl() (trait_decl, parse_error) {
    _, err := self.expect_keyword("trait")
    if err.message != "" {
        trait_decl empty
        return empty, err
    }
    name, err := self.expect_ident()
    if err.message != "" {
        trait_decl empty
        return empty, err
    }
    generics, err := self.parse_generic_params()
    if err.message != "" {
        trait_decl empty
        return empty, err
    }
    _, err = self.expect_symbol("{")
    if err.message != "" {
        trait_decl empty
        return empty, err
    }
    vec[function_sig] methods = vec[function_sig]()
    for !self.eat_symbol("}") {
        pair, err := self.parse_function(false)
        if err.message != "" {
            trait_decl empty
            return empty, err
        }
        methods.push(pair.sig)
        _, err = self.expect_symbol(";")
        if err.message != "" {
            trait_decl empty
            return empty, err
        }
    }
    trait_decl {
        name: name,
        generics: generics,
        methods: methods,
        is_public: starts_with_upper(name),
    }
}

func (parser* self) parse_function(bool require_body) (parsed_function, parse_error) {
    _, err := self.expect_keyword("func")
    if err.message != "" {
        parsed_function empty
        return empty, err
    }
    option[named_type] receiver = option::none
    if self.at_symbol("(") {
        _, err := self.expect_symbol("(")
        if err.message != "" {
            parsed_function empty
            return empty, err
        }
        receiver_tokens, err := self.parse_token_segment(vec[string] { ")" })
        if err.message != "" {
            parsed_function empty
            return empty, err
        }
        named, err := decode_receiver_type(receiver_tokens)
        if err.message != "" {
            parsed_function empty
            return empty, err
        }
        _, err = self.expect_symbol(")")
        if err.message != "" {
            parsed_function empty
            return empty, err
        }
        receiver = option::some(named)
    }
    name, err := self.expect_ident()
    if err.message != "" {
        parsed_function empty
        return empty, err
    }
    generics, err := self.parse_generic_params()
    if err.message != "" {
        parsed_function empty
        return empty, err
    }
    _, err = self.expect_symbol("(")
    if err.message != "" {
        parsed_function empty
        return empty, err
    }
    params, err := self.parse_params()
    if err.message != "" {
        parsed_function empty
        return empty, err
    }
    _, err = self.expect_symbol(")")
    if err.message != "" {
        parsed_function empty
        return empty, err
    }
    option[string] return_type = option::none
    token next = self.peek()
    if !(next.kind == token_kind::symbol && (next.value == "{" || next.value == ";")) && !(next.kind == token_kind::keyword && next.value == "where") {
        ty, err := self.parse_type_text(vec[string] { "where", "{", ";" })
        if err.message != "" {
            parsed_function empty
            return empty, err
        }
        return_type = option::some(ty)
    }
    _, err = self.parse_where_clause()
    if err.message != "" {
        parsed_function empty
        return empty, err
    }
    option[block_expr] body = option::none
    if require_body {
        b, err := self.parse_block_expr()
        if err.message != "" {
            parsed_function empty
            return empty, err
        }
        body = option::some(b)
    }
    parsed_function {
        sig: function_sig {
            name: name,
            generics: generics,
            params: params,
            return_type: return_type,
        },
        body: body,
        receiver: receiver,
    }
}

func (parser* self) parse_params() (vec[param], parse_error) {
    vec[param] params = vec[param]()
    if self.at_symbol(")") {
        return params, parse_error { message: "" }
    }
    for true {
        part, err := self.parse_named_type(vec[string] { ",", ")" })
        if err.message != "" {
            vec[param] empty
            return empty, err
        }
        params.push(param {
            name: part.name,
            type_name: part.type_name,
        })
        if !self.eat_symbol(",") || self.at_symbol(")") {
            break
        }
    }
    params, parse_error { message: "" }
}

func (parser* self) parse_generic_params() (vec[string], parse_error) {
    vec[string] generics = vec[string]()
    if !self.eat_symbol("[") {
        return generics, parse_error { message: "" }
    }
    for !self.eat_symbol("]") {
        name, err := self.expect_ident()
        if err.message != "" {
            vec[string] empty
            return empty, err
        }
        string item = name
        if self.eat_symbol(":") {
            vec[string] bounds = vec[string]()
            p, err := self.parse_path()
            if err.message != "" {
                vec[string] empty
                return empty, err
            }
            bounds.push(p)
            for self.eat_symbol("+") {
                p, err := self.parse_path()
                if err.message != "" {
                    vec[string] empty
                    return empty, err
                }
                bounds.push(p)
            }
            item = name + ": " + join_strings(bounds, " + ")
        }
        generics.push(item)
        self.eat_symbol(",")
    }
    generics, parse_error { message: "" }
}

func (parser* self) parse_where_clause() ((), parse_error) {
    if !self.eat_keyword("where") {
        return (), parse_error { message: "" }
    }
    for true {
        _, err := self.parse_type_text(vec[string] { ",", "{", ";" })
        if err.message != "" {
            return (), err
        }
        if !self.eat_symbol(",") || self.at_symbol("{") || self.at_symbol(";") {
            break
        }
    }
    (), parse_error { message: "" }
}

func (parser* self) parse_named_type(vec[string] stop_values) (named_type, parse_error) {
    segment, err := self.parse_token_segment(stop_values)
    if err.message != "" {
        named_type empty
        return empty, err
    }
    decode_named_type(segment)
}

func (parser* self) parse_token_segment(vec[string] stop_values) (vec[token], parse_error) {
    vec[token] segment = vec[token]()
    int bracket = 0
    int paren = 0
    for true {
        t, err := self.peek()
        if err.message != "" {
            vec[token] empty
            return empty, err
        }
        if t.kind == token_kind::eof {
            break
        }
        if bracket == 0 && paren == 0 && contains_string(stop_values, t.value) {
            break
        }
        if t.value == "[" {
            bracket = bracket + 1
        } else if t.value == "]" {
            bracket = bracket - 1
        } else if t.value == "(" {
            paren = paren + 1
        } else if t.value == ")" {
            if paren == 0 {
                break
            }
            paren = paren - 1
        }
        tok, err := self.advance()
        if err.message != "" {
            vec[token] empty
            return empty, err
        }
        segment.push(tok)
    }
    segment, parse_error { message: "" }
}

func (parser* self) parse_block_expr() (block_expr, parse_error) {
    _, err := self.expect_symbol("{")
    if err.message != "" {
        block_expr empty
        return empty, err
    }
    vec[stmt] statements = vec[stmt]()
    option[expr] final_expr = option::none
    for !self.at_symbol("}") {
        if self.starts_stmt() {
            s, err := self.parse_stmt()
            if err.message != "" {
                block_expr empty
                return empty, err
            }
            statements.push(s)
            continue
        }
        e, err := self.parse_expr()
        if err.message != "" {
            block_expr empty
            return empty, err
        }
        if self.eat_symbol(";") {
            statements.push(stmt::expr(expr_stmt { expr: e }))
            continue
        }
        if !self.at_symbol("}") {
            statements.push(stmt::expr(expr_stmt { expr: e }))
            continue
        }
        final_expr = option::some(e)
        break
    }
    _, err = self.expect_symbol("}")
    if err.message != "" {
        block_expr empty
        return empty, err
    }
    block_expr {
        statements: statements,
        final_expr: final_expr,
        inferred_type: option::none,
    }
}

func (parser* self) starts_stmt() bool {
        self.at_keyword("return")
            || self.at_keyword("defer")
            || self.at_keyword("sroutine")
            || self.at_cfor_start()
            || self.looks_like_typed_var_stmt()
            || self.looks_like_increment_stmt()
            || self.looks_like_assignment_stmt()
    }

func (parser* self) parse_stmt() (stmt, parse_error) {
    if self.at_keyword("defer") {
        s, err := self.parse_defer_stmt()
        if err.message != "" {
            stmt empty
            return empty, err
        }
        return stmt::defer(s), parse_error { message: "" }
    }
    if self.at_keyword("sroutine") {
        s, err := self.parse_sroutine_stmt()
        if err.message != "" {
            stmt empty
            return empty, err
        }
        return stmt::sroutine(s), parse_error { message: "" }
    }
    if self.at_keyword("return") {
        s, err := self.parse_return_stmt()
        if err.message != "" {
            stmt empty
            return empty, err
        }
        return stmt::return(s), parse_error { message: "" }
    }
    if self.at_cfor_start() {
        s, err := self.parse_cfor_stmt()
        if err.message != "" {
            stmt empty
            return empty, err
        }
        return stmt::c_for(s), parse_error { message: "" }
    }
    if self.looks_like_typed_var_stmt() {
        s, err := self.parse_typed_var_stmt(true)
        if err.message != "" {
            stmt empty
            return empty, err
        }
        return stmt::let(s), parse_error { message: "" }
    }
    if self.looks_like_increment_stmt() {
        s, err := self.parse_increment_stmt(true)
        if err.message != "" {
            stmt empty
            return empty, err
        }
        return stmt::increment(s), parse_error { message: "" }
    }
    if self.looks_like_assignment_stmt() {
        s, err := self.parse_assign_stmt(true)
        if err.message != "" {
            stmt empty
            return empty, err
        }
        return stmt::assign(s), parse_error { message: "" }
    }
    self.error_here("unexpected statement")
}

func (parser* self) parse_var_stmt(bool consume_semicolon) (var_stmt, parse_error) {
        self.error_here("let/var declarations are not supported; use explicit typed declaration")
}

func (parser* self) parse_short_var_stmt(bool consume_semicolon) (var_stmt, parse_error) {
        self.error_here("short declaration := is not supported; use explicit typed declaration")
}

func (parser* self) parse_defer_stmt() (defer_stmt, parse_error) {
    _, err := self.expect_keyword("defer")
    if err.message != "" {
        defer_stmt empty
        return empty, err
    }
    e, err := self.parse_expr()
    if err.message != "" {
        defer_stmt empty
        return empty, err
    }
    self.eat_symbol(";")
    defer_stmt { expr: e }
}

func (parser* self) parse_sroutine_stmt() (sroutine_stmt, parse_error) {
    _, err := self.expect_keyword("sroutine")
    if err.message != "" {
        sroutine_stmt empty
        return empty, err
    }
    e, err := self.parse_expr()
    if err.message != "" {
        sroutine_stmt empty
        return empty, err
    }
    self.eat_symbol(";")
    sroutine_stmt { expr: e }
}

func (parser* self) parse_typed_var_stmt(bool consume_semicolon) (var_stmt, parse_error) {
    segment, err := self.parse_token_segment(vec[string] { "=" })
    if err.message != "" {
        var_stmt empty
        return empty, err
    }
    named, err := decode_named_type(segment)
    if err.message != "" {
        var_stmt empty
        return empty, err
    }
    _, err = self.expect_symbol("=")
    if err.message != "" {
        var_stmt empty
        return empty, err
    }
    value, err := self.parse_expr()
    if err.message != "" {
        var_stmt empty
        return empty, err
    }
    if consume_semicolon {
        self.eat_symbol(";")
    }
    var_stmt {
        name: named.name,
        type_name: option::some(named.type_name),
        value: value,
    }
}

func (parser* self) parse_assign_stmt(bool consume_semicolon) (assign_stmt, parse_error) {
    name, err := self.expect_ident()
    if err.message != "" {
        assign_stmt empty
        return empty, err
    }
    _, err = self.expect_symbol("=")
    if err.message != "" {
        assign_stmt empty
        return empty, err
    }
    value, err := self.parse_expr()
    if err.message != "" {
        assign_stmt empty
        return empty, err
    }
    if consume_semicolon {
        self.eat_symbol(";")
    }
    assign_stmt {
        name: name,
        value: value,
    }
}

func (parser* self) parse_increment_stmt(bool consume_semicolon) (increment_stmt, parse_error) {
    name, err := self.expect_ident()
    if err.message != "" {
        increment_stmt empty
        return empty, err
    }
    _, err = self.expect_symbol("++")
    if err.message != "" {
        increment_stmt empty
        return empty, err
    }
    if consume_semicolon {
        self.eat_symbol(";")
    }
    increment_stmt {
        name: name,
    }
}

func (parser* self) parse_cfor_stmt() (c_for_stmt, parse_error) {
    _, err := self.expect_keyword("for")
    if err.message != "" {
        c_for_stmt empty
        return empty, err
    }
    _, err = self.expect_symbol("(")
    if err.message != "" {
        c_for_stmt empty
        return empty, err
    }
    init, err := self.parse_for_clause_stmt()
    if err.message != "" {
        c_for_stmt empty
        return empty, err
    }
    _, err = self.expect_symbol(";")
    if err.message != "" {
        c_for_stmt empty
        return empty, err
    }
    condition, err := self.parse_expr()
    if err.message != "" {
        c_for_stmt empty
        return empty, err
    }
    _, err = self.expect_symbol(";")
    if err.message != "" {
        c_for_stmt empty
        return empty, err
    }
    step, err := self.parse_for_clause_stmt()
    if err.message != "" {
        c_for_stmt empty
        return empty, err
    }
    _, err = self.expect_symbol(")")
    if err.message != "" {
        c_for_stmt empty
        return empty, err
    }
    body, err := self.parse_block_expr()
    if err.message != "" {
        c_for_stmt empty
        return empty, err
    }
    c_for_stmt {
        init: box(init),
        condition: condition,
        step: box(step),
        body: body,
    }
}

func (parser* self) parse_for_clause_stmt() (stmt, parse_error) {
    if self.looks_like_typed_var_stmt() {
        s, err := self.parse_typed_var_stmt(false)
        if err.message != "" {
            stmt empty
            return empty, err
        }
        return stmt::let(s), parse_error { message: "" }
    }
    if self.looks_like_increment_stmt() {
        s, err := self.parse_increment_stmt(false)
        if err.message != "" {
            stmt empty
            return empty, err
        }
        return stmt::increment(s), parse_error { message: "" }
    }
    if self.looks_like_assignment_stmt() {
        s, err := self.parse_assign_stmt(false)
        if err.message != "" {
            stmt empty
            return empty, err
        }
        return stmt::assign(s), parse_error { message: "" }
    }
    stmt empty
}

func (parser* self) parse_return_stmt() (return_stmt, parse_error) {
    _, err := self.expect_keyword("return")
    if err.message != "" {
        return_stmt empty
        return empty, err
    }
    if self.eat_symbol(";") {
        return_stmt r
        r = return_stmt { value: option::none }
        return r, parse_error { message: "" }
    }
    value, err := self.parse_expr()
    if err.message != "" {
        return_stmt empty
        return empty, err
    }
    self.eat_symbol(";")
    return_stmt {
        value: option::some(value),
    }
}

func (parser* self) parse_expr() (expr, parse_error) {
    if self.at_keyword("select") {
        e, err := self.parse_select_expr()
        if err.message != "" {
            expr empty
            return empty, err
        }
        return e, parse_error { message: "" }
    }
    if self.at_keyword("switch") {
        e, err := self.parse_switch_expr()
        if err.message != "" {
            expr empty
            return empty, err
        }
        return e, parse_error { message: "" }
    }
    if self.at_keyword("if") {
        e, err := self.parse_if_expr()
        if err.message != "" {
            expr empty
            return empty, err
        }
        return e, parse_error { message: "" }
    }
    if self.at_keyword("for") {
        e, err := self.parse_for_expr()
        if err.message != "" {
            expr empty
            return empty, err
        }
        return e, parse_error { message: "" }
    }
    self.parse_binary_expr(0)
}

func (parser* self) parse_select_expr() (expr, parse_error) {
        self.expect_keyword("select")
        self.expect_symbol("{")
        string mode = ""
        vec[expr] recv_args = vec[expr]()
        vec[expr] send_args = vec[expr]()
        option[expr] timeout_arg = option[expr].none
        bool has_default = false
        string callee_name = ""
        vec[expr] args = vec[expr]()
        int ri = 0
        int si = 0
        for !self.eat_symbol("}") {
            self.expect_keyword("case")
            if self.eat_keyword("default") {
                if has_default {
                    return self.error_here("duplicate default case in select")
                }
                has_default = true
                self.expect_symbol(":")
                self.eat_symbol(";")
                continue
            }
            case_expr, err := self.parse_expr()
            if err.message != "" {
                expr empty
                return empty, err
            }
            self.expect_symbol(":")
            self.eat_symbol(";")
            switch case_expr {
                expr.call(call_value) : {
                    switch call_value.callee.value {
                        expr.name(name_value) : {
                            if name_value.name == "recv" {
                                if mode != "" && mode != "recv" {
                                    return self.error_here("select cannot mix recv and send cases")
                                }
                                mode = "recv"
                                if call_value.args.len() == 0 {
                                    return self.error_here("select recv case requires at least one channel")
                                }
                                ri = 0
                                for ri < call_value.args.len() {
                                    recv_args.push(call_value.args[ri])
                                    ri = ri + 1
                                }
                            } else if name_value.name == "send" {
                                if mode != "" && mode != "send" {
                                    return self.error_here("select cannot mix recv and send cases")
                                }
                                mode = "send"
                                if call_value.args.len() < 2 || (call_value.args.len() % 2) != 0 {
                                    return self.error_here("select send case expects channel/value pairs")
                                }
                                si = 0
                                for si < call_value.args.len() {
                                    send_args.push(call_value.args[si])
                                    si = si + 1
                                }
                            } else if name_value.name == "timeout" || name_value.name == "after" {
                                if timeout_arg.is_some() {
                                    return self.error_here("duplicate timeout case in select")
                                }
                                if call_value.args.len() != 1 {
                                    return self.error_here("select timeout case expects one tick argument")
                                }
                                timeout_arg = option[expr].some(call_value.args[0])
                            } else {
                                return self.error_here("unsupported select case expression")
                            }
                        }
                        _ : return self.error_here("select case must be recv/send/timeout call"),
                    }
                }
                _ : return self.error_here("select case must be call expression"),
            }
        }
        if timeout_arg.is_some() && has_default {
            return self.error_here("select cannot combine timeout and default")
        }
        if mode == "" {
            return self.error_here("select requires recv(...) or send(...) case")
        }
        callee_name = ""
        args = vec[expr]()
        if mode == "recv" {
            if recv_args.len() == 0 {
                return self.error_here("select recv requires at least one channel")
            }
            callee_name = "select_recv"
            ri = 0
            for ri < recv_args.len() {
                args.push(recv_args[ri])
                ri = ri + 1
            }
            if timeout_arg.is_some() {
                callee_name = "select_recv_timeout"
                args.push(timeout_arg.unwrap())
            } else if has_default {
                callee_name = "select_recv_default"
            }
        } else {
            if send_args.len() < 2 || (send_args.len() % 2) != 0 {
                return self.error_here("select send requires channel/value pairs")
            }
            callee_name = "select_send"
            si = 0
            for si < send_args.len() {
                args.push(send_args[si])
                si = si + 1
            }
            if timeout_arg.is_some() {
                callee_name = "select_send_timeout"
                args.push(timeout_arg.unwrap())
            } else if has_default {
                callee_name = "select_send_default"
            }
        }
        build_call_expr(callee_name, args)
}

func (parser* self) parse_switch_expr() (expr, parse_error) {
        self.expect_keyword("switch")
        subject, err := self.parse_expr()
        if err.message != "" {
            expr empty
            return empty, err
        }
        vec[switch_arm] arms = vec[switch_arm]()
        for !self.eat_symbol("}") {
            pattern, err := self.parse_pattern()
            if err.message != "" {
                expr empty
                return empty, err
            }
            self.expect_symbol(":")
            expr, err := self.parse_expr()
            if err.message != "" {
                expr empty
                return empty, err
            }
                pattern: pattern,
                expr: expr,
            })
            self.eat_symbol(",")
        }
        expr::switch(switch_expr {
            subject: box(subject),
            arms: arms,
            inferred_type: option::none,
        })
}

func (parser* self) parse_if_expr() (expr, parse_error) {
        self.expect_keyword("if")
        condition, err := self.parse_expr()
        if err.message != "" {
            expr empty
            return empty, err
        }
                if self.at_keyword("if") {
                    option::some(box(self.parse_if_expr()))
                } else {
                    option::some(box(expr::block(self.parse_block_expr())))
                }
            } else {
                option::none
            }
        expr::if(if_expr {
            condition: box(condition),
            then_branch: then_branch,
            else_branch: else_branch,
            inferred_type: option::none,
        })
}

func (parser* self) parse_for_expr() (expr, parse_error) {
        self.expect_keyword("for")
        
        if self.at_symbol("{") {
            body, err := self.parse_block_expr()
            if err.message != "" {
                expr empty
                return empty, err
            }
            return expr::for(for_expr {
                init: option::none,
                condition: option::none,
                post: option::none,
                names: vec[string](),
                iterable: option::none,
                body: body,
                inferred_type: option::none,
            }))
        }
        
        if self.at_symbol("(") {
            self.expect_symbol("(")
            init, err := self.parse_for_clause_stmt()
            if err.message != "" {
                expr empty
                return empty, err
            }
            self.expect_symbol(";")
            condition, err := self.parse_expr()
            if err.message != "" {
                expr empty
                return empty, err
            }
            post, err := self.parse_for_clause_stmt()
            if err.message != "" {
                expr empty
                return empty, err
            }
            _, err := self.expect_symbol(")")
            if err.message != "" { expr empty; return empty, err }
            body, err := self.parse_block_expr()
            if err.message != "" {
                expr empty
                return empty, err
            }
            return expr::for(for_expr {
                init: option::some(box(init)),
                condition: option::some(box(condition)),
                post: option::some(box(post)),
                names: vec[string](),
                iterable: option::none,
                body: body,
                inferred_type: option::none,
            }))
        }
        
        token, err := self.peek()
        if err.message != "" {
            token empty
            return empty, err
        }
            name, err := self.expect_ident()
            if err.message != "" {
                string empty
                return empty, err
            }
            iterable, err := self.parse_expr()
            if err.message != "" {
                expr empty
                return empty, err
            }
            return expr::for(for_expr {
                init: option::none,
                condition: option::none,
                post: option::none,
                names: vec[string] { name },
                iterable: option::some(box(iterable)),
                body: body,
                inferred_type: option::none,
            }))
        }
        
        condition, err := self.parse_expr()
        if err.message != "" {
            expr empty
            return empty, err
        }
        expr::for(for_expr {
            init: option::none,
            condition: option::some(box(condition)),
            post: option::none,
            names: vec[string](),
            iterable: option::none,
            body: body,
            inferred_type: option::none,
        })
}

func (parser* self) parse_pattern() (pattern, parse_error) {
        if self.eat_ident_value("_") {
            return pattern::wildcard(wildcard_pattern {}))
        }
        token, err := self.peek()
        if err.message != "" {
            token empty
            return empty, err
        }
            self.advance()
            return pattern::literal(literal_pattern {
                value: expr::int(int_expr {
                    value: token.value,
                    inferred_type: option::none,
                }),
            }))
        }
        if token.kind == token_kind::string {
            self.advance()
            return pattern::literal(literal_pattern {
                value: expr::string(string_expr {
                    value: token.value,
                    inferred_type: option::none,
                }),
            }))
        }
        if self.at_keyword("true") {
            self.advance()
            return pattern::literal(literal_pattern {
                value: expr::bool(bool_expr {
                    value: true,
                    inferred_type: option::none,
                }),
            }))
        }
        if self.at_keyword("false") {
            self.advance()
            return pattern::literal(literal_pattern {
                value: expr::bool(bool_expr {
                    value: false,
                    inferred_type: option::none,
                }),
            }))
        }
        path, err := self.parse_path()
        if err.message != "" {
            string empty
            return empty, err
        }
            vec[pattern] args = vec[pattern]()
            if !self.at_symbol(")") {
                for true {
                    args.push(self.parse_pattern())
                    if !self.eat_symbol(",") || self.at_symbol(")") {
                        break
                    }
                }
            }
            _, err := self.expect_symbol(")")
            if err.message != "" { expr empty; return empty, err }
            return pattern::variant(variant_pattern {
                path: path,
                args: args,
            }))
        }
        if path_contains_dot(path) || starts_with_upper(path) {
            return pattern::variant(variant_pattern {
                path: path,
                args: vec[pattern](),
            }))
        }
        pattern::name(name_pattern { name: path })
}

func (parser* self) parse_binary_expr(int min_precedence) (expr, parse_error) {
        expr, err := self.parse_unary_expr()
        if err.message != "" {
            expr empty
            return empty, err
        }
        for true {
            token, err := self.peek()
            if err.message != "" {
                token empty
                return empty, err
            }
                break
            }
            op, err := self.advance()
            if err.message != "" {
                string empty
                return empty, err
            }
            expr = expr::binary(binary_expr {
                left: box(expr),
                op: op,
                right: box(rhs),
                inferred_type: option::none,
            })
        }
        expr
}

func (parser* self) parse_unary_expr() (expr, parse_error) {
    if self.eat_symbol("&") {
        bool mutable = false
        target, err := self.parse_unary_expr()
        if err.message != "" {
            expr empty
            return empty, err
        }
        return expr::borrow(borrow_expr {
            target: box(target),
            mutable: mutable,
            inferred_type: option::none,
        }), parse_error { message: "" }
    }
    self.parse_call_expr()
}

func (parser* self) parse_call_expr() (expr, parse_error) {
        expr, err := self.parse_primary_expr()
        if err.message != "" {
            expr empty
            return empty, err
        }
        for true {
            if self.eat_symbol("(") {
                vec[expr] args = vec[expr]()                
                if !self.at_symbol(")") {
                    for true {
                        args.push(self.parse_expr())
                        if !self.eat_symbol(",") || self.at_symbol(")") {
                            break
                        }
                    }
                }
                _, err := self.expect_symbol(")")
            if err.message != "" { expr empty; return empty, err }
                expr = expr::call(call_expr {
                    callee: box(expr),
                    args: args,
                    inferred_type: option::none,
                })
                continue
            }
            if self.eat_symbol(".") {
                expr = expr::member(member_expr {
                    target: box(expr),
                    member: self.expect_ident(),
                    inferred_type: option::none,
                })
                continue
            }
            if self.eat_symbol(":") {
                self.expect_symbol(":")
                expr = expr::member(member_expr {
                    target: box(expr),
                    member: self.expect_ident(),
                    inferred_type: option::none,
                })
                continue
            }
            if self.eat_symbol("[") {
                index, err := self.parse_expr()
                if err.message != "" {
                    expr empty
                    return empty, err
                }
                self.expect_symbol("]")
                expr = expr::index(index_expr {
                    target: box(expr),
                    index: box(index),
                    inferred_type: option::none,
                })
                continue
            }
            break
        }
        expr
    }

func (parser* self) parse_primary_expr() (expr, parse_error) {
        token, err := self.peek()
        if err.message != "" {
            token empty
            return empty, err
        }
            self.advance()
            return expr::int(int_expr {
                value: token.value,
                inferred_type: option::none,
            }))
        }
        if token.kind == token_kind::string {
            self.advance()
            return expr::string(string_expr {
                value: token.value,
                inferred_type: option::none,
            }))
        }
        if self.at_keyword("true") {
            self.advance()
            return expr::bool(bool_expr {
                value: true,
                inferred_type: option::none,
            }))
        }
        if self.at_keyword("false") {
            self.advance()
            return expr::bool(bool_expr {
                value: false,
                inferred_type: option::none,
            }))
        }
        if self.at_keyword("nil") {
            self.advance()
            return expr::name(name_expr {
                name: "nil",
                inferred_type: option::none,
            }))
        }
        if self.at_symbol("{") {
            return expr::block(self.parse_block_expr()))
        }
        if self.eat_symbol("(") {
            expr, err := self.parse_expr()
            if err.message != "" {
                expr empty
                return empty, err
            }
            return expr
        }
        if self.at_symbol("[") {
            bracket, err := self.parse_bracket_group()
            if err.message != "" {
                expr empty
                return empty, err
            }
            type_text := bracket
            token token = self.peek().unwrap()            if token.kind != token_kind::symbol || token.value != "{" {
                seg, err := self.parse_token_segment(vec[string] { "{" })
                if err.message != "" {
                    expr empty
                    return empty, err
                }
                type_text = type_text + " " + join_token_values(seg)
            }
            self.expect_symbol("{")
            vec[expr] items = vec[expr]()
            if !self.at_symbol("}") {
                for true {
                    items.push(self.parse_expr())
                    if !self.eat_symbol(",") || self.at_symbol("}") {
                        break
                    }
                }
            }
            self.expect_symbol("}")
            return expr::array(array_literal { type_text: option::some(type_text.trim()), items: items }))
        }
        if token.kind == token_kind::ident && token.value == "map" {
            self.advance()
            bracket, err := self.parse_bracket_group()
            if err.message != "" {
                expr empty
                return empty, err
            }
            type_text := "map" + bracket
            token2 := self.peek().unwrap()
            if token2.kind == token_kind::ident || token2.kind == token_kind::symbol {
                seg, err := self.parse_token_segment(vec[string] { "{" })
                if err.message != "" {
                    expr empty
                    return empty, err
                }
                type_text = type_text + " " + join_token_values(seg)
            }
            self.expect_symbol("{")
            vec[map_entry] entries = vec[map_entry]()
            if !self.at_symbol("}") {
                for true {
                    key, err := self.parse_expr()
                    if err.message != "" {
                        expr empty
                        return empty, err
                    }
                    self.expect_symbol(":")
                    value, err := self.parse_expr()
                    if err.message != "" {
                        expr empty
                        return empty, err
                    }
                    entries.push(map_entry { key: key, value: value })
                    if !self.eat_symbol(",") || self.at_symbol("}") {
                        break
                    }
                }
            }
            self.expect_symbol("}")
            return expr::map(map_literal { type_text: option::some(type_text.trim()), entries: entries }))
        }
        expr::name(name_expr {
            name: self.expect_ident(),
            inferred_type: option::none,
        })
    }

func (parser* self) binary_precedence(string op) int {
        switch op {
            "||" : 1,
            "&&" : 2,
            "==" : 3,
            "!=" : 3,
            "<" : 4,
            "<=" : 4,
            ">" : 4,
            ">=" : 4,
            "+" : 5,
            "-" : 5,
            "*" : 6,
            "/" : 6,
            "%" : 6,
            _ : -1,
        }
    }

func (parser* self) parse_use_path() (string, parse_error) {
        vec[string] parts = vec[string]()
        parts.push(self.expect_ident())
        for self.eat_symbol(".") {
            if self.eat_symbol("{") {
                vec[string] members = vec[string]()
                for !self.eat_symbol("}") {
                    member, err := self.expect_ident()
                    if err.message != "" {
                        expr empty
                        return empty, err
                    }
                    string text = if self.eat_keyword("as") {
                            member + " as " + self.expect_ident()
                        } else {
                            member
                        }
                    members.push(text)
                    self.eat_symbol(",")
                }
                return join_strings(parts, ".") + ".{" + join_strings(members, ", ") + "}")
            }
            parts.push(self.expect_ident())
        }
        join_strings(parts, ".")
    }

func (parser* self) parse_path() (string, parse_error) {
    vec[string] parts = vec[string]()
    ident, err := self.expect_ident()
    if err.message != "" {
        string empty
        return empty, err
    }
    parts.push(ident)
    for self.eat_symbol(".") {
        p, err := self.expect_ident()
        if err.message != "" {
            string empty
            return empty, err
        }
        parts.push(p)
    }
    for self.at_symbol(":") && self.peek_at(1).unwrap().kind == token_kind::symbol && self.peek_at(1).unwrap().value == ":" {
        _, err := self.expect_symbol(":")
        if err.message != "" {
            string empty
            return empty, err
        }
        _, err = self.expect_symbol(":")
        if err.message != "" {
            string empty
            return empty, err
        }
        p, err := self.expect_ident()
        if err.message != "" {
            string empty
            return empty, err
        }
        parts.push(p)
    }
    if self.at_symbol("[") {
        last := parts.pop().unwrap()
        bg, err := self.parse_bracket_group()
        if err.message != "" {
            string empty
            return empty, err
        }
        parts.push(last + bg)
    }
    join_strings(parts, "."), parse_error { message: "" }
}

func (parser* self) parse_type_text(vec[string] stop_values) (string, parse_error) {
    vec[string] parts = vec[string]()
    int bracket = 0
    int paren = 0
    for true {
        t, err := self.peek()
        if err.message != "" {
            string empty
            return empty, err
        }
        if t.kind == token_kind::eof {
            break
        }
        if bracket == 0 && paren == 0 && contains_string(stop_values, t.value) {
            break
        }
        if t.value == "[" {
            bracket = bracket + 1
        } else if t.value == "]" {
            bracket = bracket - 1
        } else if t.value == "(" {
            paren = paren + 1
        } else if t.value == ")" {
            if paren == 0 {
                break
            }
            paren = paren - 1
        }
        tok, err := self.advance()
        if err.message != "" {
            string empty
            return empty, err
        }
        parts.push(tok.value)
    }
    normalize_type_text(join_strings(parts, " ")), parse_error { message: "" }
}

func (parser* self) parse_bracket_group() (string, parse_error) {
    vec[string] parts = vec[string]()
    tok, err := self.advance()
    if err.message != "" {
        string empty
        return empty, err
    }
    parts.push(tok.value)
    int depth = 1
    for depth > 0 {
        t, err := self.advance()
        if err.message != "" {
            string empty
            return empty, err
        }
        parts.push(t.value)
        if t.value == "[" {
            depth = depth + 1
        } else if t.value == "]" {
            depth = depth - 1
        }
    }
    join_strings(parts, " ").replace("[ ", "[").replace(" ]", "]"), parse_error { message: "" }
})
                .replace(" ,", ",")
        
    }

func (parser* self) at(token_kind kind) bool {
        self.peek().unwrap().kind == kind
    }

func (parser* self) at_keyword(string value) bool {
        token token = self.peek().unwrap()        token.kind == token_kind::keyword && token.value == value
    }

func (parser* self) at_symbol(string value) bool {
        token token = self.peek().unwrap()        token.kind == token_kind::symbol && token.value == value
    }

func (parser* self) at_symbol_after_keyword(string value) bool {
        token first = self.peek().unwrap()        if first.kind != token_kind::keyword {
            return false
        }
        token second = self.peek_at(1).unwrap()        second.kind == token_kind::symbol && second.value == value
    }

func (parser* self) at_cfor_start() bool {
        self.at_keyword("for") && self.peek_at(1).unwrap().kind == token_kind::symbol && self.peek_at(1).unwrap().value == "("
    }

func (parser* self) looks_like_assignment_stmt() bool {
        token first = self.peek().unwrap()        token second = self.peek_at(1).unwrap()        first.kind == token_kind::ident && second.kind == token_kind::symbol && second.value == "="
    }

func (parser* self) looks_like_short_var_stmt() bool {
        false
    }

func (parser* self) looks_like_increment_stmt() bool {
        token first = self.peek().unwrap()        token second = self.peek_at(1).unwrap()        first.kind == token_kind::ident && second.kind == token_kind::symbol && second.value == "++"
    }

func (parser* self) looks_like_typed_var_stmt() bool {
        int offset = self.find_top_level_symbol_offset("=")        if offset <= 0 {
            return false
        }
        decode_named_type(slice_tokens(self.tokens, self.index, self.index + offset)).is_ok()
    }

func (parser* self) eat_keyword(string value) bool {
        if self.at_keyword(value) {
            self.advance().unwrap()
            return true
        }
        false
    }

func (parser* self) eat_ident_value(string value) bool {
        token token = self.peek().unwrap()        if token.kind == token_kind::ident && token.value == value {
            self.advance().unwrap()
            return true
        }
        false
    }

func (parser* self) eat_symbol(string value) bool {
        if self.at_symbol(value) {
            self.advance().unwrap()
            return true
        }
        false
    }

func (parser* self) expect_keyword(string value) (token, parse_error) {
    t, err := self.peek()
    if err.message != "" {
        token empty
        return empty, err
    }
    if t.kind == token_kind::keyword && t.value == value {
        return self.advance()
    }
    parse_error {
        message: "expected keyword " + value,
        line: t.line,
        column: t.column,
    }
}

func (parser* self) expect_symbol(string value) (token, parse_error) {
    t, err := self.peek()
    if err.message != "" {
        token empty
        return empty, err
    }
    if t.kind == token_kind::symbol && t.value == value {
        return self.advance()
    }
    parse_error {
        message: "expected symbol " + value,
        line: t.line,
        column: t.column,
    }
}

func (parser* self) expect_ident() (string, parse_error) {
    t, err := self.peek()
    if err.message != "" {
        string empty
        return empty, err
    }
    if t.kind == token_kind::ident {
        _, err := self.advance()
        if err.message != "" {
            string empty
            return empty, err
        }
        return t.value, parse_error { message: "" }
    }
    if t.kind == token_kind::keyword && t.value == "self" {
        _, err := self.advance()
        if err.message != "" {
            string empty
            return empty, err
        }
        return t.value, parse_error { message: "" }
    }
    parse_error {
        message: "expected identifier",
        line: t.line,
        column: t.column,
    }
}

func (parser* self) peek() (token, parse_error) {
        self.peek_at(0)
    }

func (parser* self) peek_at(int offset) (token, parse_error) {
        if self.index >= len(self.tokens) {
            return parse_error {
                message: "unexpected eof",
                line: 0,
                column: 0,
            }
        }
        int target = self.index + offset        if target >= len(self.tokens) {
            target = len(self.tokens) - 1
        }
        self.tokens[target]
    }

func (parser* self) advance() (token, parse_error) {
    t, err := self.peek()
    if err.message != "" {
        token empty
        return empty, err
    }
    self.index = self.index + 1
    t, parse_error { message: "" }
}

func (parser* self) error_here(string message) parse_error {
        token token = self.peek().unwrap()
        parse_error {
            message: message,
            line: token.line,
            column: token.column,
        }
    }

func (parser* self) find_top_level_symbol_offset(string value) int {
        int bracket = 0
        int paren = 0
        int offset = 0
        for self.index + offset < len(self.tokens) {
            token := self.tokens[self.index + offset]
            if token.kind == token_kind::eof {
                break
            }
            if token.value == "[" {
                bracket = bracket + 1
            } else if token.value == "]" {
                bracket = bracket - 1
            } else if token.value == "(" {
                paren = paren + 1
            } else if token.value == ")" {
                if paren == 0 {
                    break
                }
                paren = paren - 1
            } else if bracket == 0 && paren == 0 && token.value == value {
                return offset
            } else if bracket == 0 && paren == 0 && (token.value == ";" || token.value == "}") {
                break
            }
            offset = offset + 1
        }
        -1
    }

func build_call_expr(string callee_name, vec[expr] args) expr {
    expr::call(call_expr {
        callee: box(expr::name(name_expr {
            name: callee_name,
            inferred_type: option::none,
        })),
        args: args,
        inferred_type: option::none,
    })
}

struct parsed_function {
    function_sig sig
    option[block_expr] body
    option[named_type] receiver
}

struct named_type {
    string name
    string type_name
}

func decode_receiver_type(vec[token] tokens) (named_type, parse_error) {
    colon := find_token_value(tokens, ":")
    if colon >= 0 {
        return decode_named_type(tokens
    }
    if tokens.len() >= 2 && tokens[0].kind == token_kind::ident {
        return named_type {
            name: tokens[0].value,
            type_name: normalize_type_text(join_token_values(slice_tokens(tokens, 1, len(tokens)))),
        })
    }
    parse_error {
        message: "expected receiver in '(name Type)' or '(name: Type)' form",
        line: 0,
        column: 0,
    }
}

func decode_named_type(vec[token] tokens) (named_type, parse_error) {
    int colon = find_token_value(tokens, ":")
    if colon >= 0 {
        name_tokens := slice_tokens(tokens, 0, colon)
        type_tokens := slice_tokens(tokens, colon + 1, len(tokens))
        return named_type {
            name: normalize_type_text(join_token_values(name_tokens)),
            type_name: normalize_type_text(join_token_values(type_tokens)),
        }
    }
    int split = find_decl_name_index(tokens)
    if split <= 0 {
        return parse_error {
            message: "expected typed name",
            line: 0,
            column: 0,
        }
    }
    named_type {
        name: tokens[split].value,
        type_name: normalize_type_text(join_token_values(slice_tokens(tokens, 0, split))),
    }
}

func slice_tokens(vec[token] tokens, int start, int end) vec[token] {
    vec[token] out = vec[token]()
    int i = start
    for i < end {
        out.push(tokens[i])
        i = i + 1
    }
    out
}

func join_token_values(vec[token] tokens) string {
    vec[string] parts = vec[string]()
    for token in tokens {
        parts.push(token.value)
    }
    join_strings(parts, " ")
}

func find_token_value(vec[token] tokens, string value) int {
    int bracket = 0
    int paren = 0
    int i = 0
    for i < len(tokens) {
        token := tokens[i]
        if token.value == "[" {
            bracket = bracket + 1
        } else if token.value == "]" {
            bracket = bracket - 1
        } else if token.value == "(" {
            paren = paren + 1
        } else if token.value == ")" {
            paren = paren - 1
        } else if bracket == 0 && paren == 0 && token.value == value {
            return i
        }
        i = i + 1
    }
    -1
}

func find_decl_name_index(vec[token] tokens) int {
    int bracket = 0
    int paren = 0
    int index = -1
    int i = 0
    for i < len(tokens) {
        token := tokens[i]
        if token.value == "[" {
            bracket = bracket + 1
        } else if token.value == "]" {
            bracket = bracket - 1
        } else if token.value == "(" {
            paren = paren + 1
        } else if token.value == ")" {
            paren = paren - 1
        } else if bracket == 0 && paren == 0 && token.kind == token_kind::ident {
            index = i
        }
        i = i + 1
    }
    index
}

func normalize_type_text(string text) string {
    text
        .replace(" . ", ".")
        .replace("[ ", "[")
        .replace(" ]", "]")
        .replace("( ", "(")
        .replace(" )", ")")
        .replace(" ,", ",")
        .replace("[] ", "[]")
        .replace(" [", "[")
}

func contains_string(vec[string] values, string target) bool {
    for value in values {
        if value == target {
            return true
        }
    }
    false
}

func join_strings(vec[string] values, string sep) string {
    string out = ""
    bool first = true
    for value in values {
        if !first {
            out = out + sep
        }
        out = out + value
        first = false
    }
    out
}

func path_contains_dot(string path) bool {
    int i = 0
    for i < len(path) {
        if char_at(path, i) == "." {
            return true
        }
        i = i + 1
    }
    false
}

func starts_with_upper(string text) bool {
    if text == "" {
        return false
    }
    string ch = char_at(text, 0)
    switch ch {
        "a" : true,
        "b" : true,
        "c" : true,
        "d" : true,
        "e" : true,
        "f" : true,
        "g" : true,
        "h" : true,
        "i" : true,
        "j" : true,
        "k" : true,
        "l" : true,
        "m" : true,
        "n" : true,
        "o" : true,
        "p" : true,
        "q" : true,
        "r" : true,
        "s" : true,
        "t" : true,
        "u" : true,
        "v" : true,
        "w" : true,
        "x" : true,
        "y" : true,
        "z" : true,
        _ : false,
    }
}
