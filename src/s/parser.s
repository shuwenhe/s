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

func parse_source(string source) result[source_file, parse_error] {
    switch new_lexer(source).tokenize() {
        result::ok(tokens) : parse_tokens(tokens),
        result::err(err) : result::err(parse_error {
            message: err.message,
            line: err.line,
            column: err.column,
        }),
    }
}

func parse_tokens(vec[token] tokens) result[source_file, parse_error] {
    parser parser = parser {        tokens: tokens,
        index: 0,
    }
    parser.parse_source_file()
}

impl parser {
    int global_parse_depth = 0    func log_depth(string msg) {
        print(msg)
    }

    func parse_source_file(mut self) result[source_file, parse_error] {
        global_parse_depth = global_parse_depth + 1
        log_depth("parse_source_file depth: " + to_string(global_parse_depth))
        self.expect_keyword("package")?
        string pkg = self.parse_path()?        vec[use_decl] uses = vec[use_decl]()        vec[item] items = vec[item]()
        while self.at_keyword("use") {
            uses.push(self.parse_use_decl()?)
        }

        while !self.at(token_kind::eof) {
            if self.at_keyword("const") && self.at_symbol_after_keyword("(") {
                vec[const_decl] consts = self.parse_const_group_items()?                int ci = 0                while ci < consts.len() {
                    items.push(item::const(consts[ci]));
                    ci = ci + 1
                }
                continue
            }
            items.push(self.parse_item()?)
        }

        global_parse_depth = global_parse_depth - 1
        log_depth("parse_source_file exit depth: " + to_string(global_parse_depth))
        result::ok(source_file {
            pkg: pkg,
            uses: uses,
            items: items,
        })
    }

    func parse_use_decl(mut self) result[use_decl, parse_error] {
        self.expect_keyword("use")?
        string path = self.parse_use_path()?        option[string] alias =            if self.at_keyword("as") {
                self.advance()?
                option::some(self.expect_ident()?)
            } else {
                option::none
            }
        result::ok(use_decl {
            path: path,
            alias: alias,
        })
    }

    func parse_item(mut self) result[item, parse_error] {
        if self.at_keyword("func") {
            parsed_function parsed = self.parse_function(true)?
            switch parsed.receiver {
                option::some(r) : {
                    function_decl method = function_decl {                        sig: parsed.sig,
                        body: parsed.body,
                        is_public: starts_with_upper(parsed.sig.name),
                    }
                    impl_decl impl_decl = impl_decl {                        target: r.type_name,
                        trait_name: option::none,
                        generics: vec[string](),
                        methods: vec[function_decl] { method },
                    }
                    return result::ok(item::impl(impl_decl))
                },
                option::none : {
                    return result::ok(item::function(parsed))
                }
            }
        }
        if self.at_keyword("const") {
            return result::ok(item::const(self.parse_const_decl()?))
        }
        if self.at_keyword("struct") {
            return result::ok(item::struct(self.parse_struct_decl()?))
        }
        if self.at_keyword("enum") {
            return result::ok(item::enum(self.parse_enum_decl()?))
        }
        if self.at_keyword("trait") {
            return result::ok(item::trait(self.parse_trait_decl()?))
        }
        if self.at_keyword("impl") {
            return result::ok(item::impl(self.parse_impl_decl()?))
        }
        result::err(self.error_here("unexpected token"))
    }

    func parse_const_decl(mut self) result[const_decl, parse_error] {
        self.expect_keyword("const")?
        const_decl entry = self.parse_const_entry(false, 0)?        self.eat_symbol(";")
        result::ok(entry)
    }

    func parse_const_group_items(mut self) result[vec[const_decl], parse_error] {
        self.expect_keyword("const")?
        self.expect_symbol("(")?
        vec[const_decl] out = vec[const_decl]()        int iota_index = 0        while !self.eat_symbol(")") {
            if self.eat_symbol(";") || self.eat_symbol(",") {
                continue
            }
            out.push(self.parse_const_entry(true, iota_index)?);
            iota_index = iota_index + 1
            self.eat_symbol(";")
            self.eat_symbol(",")
        }
        result::ok(out)
    }

    func parse_const_entry(mut self, bool allow_omitted_value, int iota_index) result[const_decl, parse_error] {
        string name = self.expect_ident()?        option[expr] value = option::none        if self.eat_symbol("=") {
            value = option::some(self.parse_expr()?)
        } else if !allow_omitted_value {
            return result::err(self.error_here("expected symbol ="))
        }
        result::ok(const_decl {
            name: name,
            value: value,
            iota_index: iota_index,
        })
    }

    func parse_function_decl(mut self) result[function_decl, parse_error] {
        parsed_function pair = self.parse_function(true)?        if pair.receiver.is_some() {
            return result::err(self.error_here("method receiver not allowed in this context"))
        }
        result::ok(function_decl {
            sig: pair.sig,
            body: pair.body,
            is_public: starts_with_upper(pair.sig.name),
        })
    }

    func parse_struct_decl(mut self) result[struct_decl, parse_error] {
        self.expect_keyword("struct")?
        string name = self.expect_ident()?        vec[string] generics = self.parse_generic_params()?        self.expect_symbol("{")?
        vec[field] fields = vec[field]()
        while !self.eat_symbol("}") {
            named_type field = self.parse_named_type(vec[string] { ",", "}" })?            fields.push(field {
                name: field.name,
                type_name: field.type_name,
                is_public: starts_with_upper(field.name),
            })
            self.eat_symbol(",")
        }

        result::ok(struct_decl {
            name: name,
            generics: generics,
            fields: fields,
            is_public: starts_with_upper(name),
        })
    }

    func parse_enum_decl(mut self) result[enum_decl, parse_error] {
        self.expect_keyword("enum")?
        string name = self.expect_ident()?        vec[string] generics = self.parse_generic_params()?        self.expect_symbol("{")?
        vec[enum_variant] variants = vec[enum_variant]()
        while !self.eat_symbol("}") {
            string variant_name = self.expect_ident()?            option[string] payload =                if self.eat_symbol("(") {
                    string ty = self.parse_type_text(vec[string] { ")" })?                    self.expect_symbol(")")?
                    option::some(ty)
                } else {
                    option::none
                }
            variants.push(enum_variant {
                name: variant_name,
                payload: payload,
            })
            self.eat_symbol(",")
        }

        result::ok(enum_decl {
            name: name,
            generics: generics,
            variants: variants,
            is_public: starts_with_upper(name),
        })
    }

    func parse_trait_decl(mut self) result[trait_decl, parse_error] {
        self.expect_keyword("trait")?
        string name = self.expect_ident()?        vec[string] generics = self.parse_generic_params()?        self.expect_symbol("{")?
        vec[function_sig] methods = vec[function_sig]()
        while !self.eat_symbol("}") {
            let pair = self.parse_function(false)?
            methods.push(pair.sig)
            self.expect_symbol(";")?
        }

        result::ok(trait_decl {
            name: name,
            generics: generics,
            methods: methods,
            is_public: starts_with_upper(name),
        })
    }

    func parse_impl_decl(mut self) result[impl_decl, parse_error] {
        self.expect_keyword("impl")?
        vec[string] generics = self.parse_generic_params()?        string first = self.parse_path()?        option[string] trait_name = option::none        string target = first
        if self.eat_keyword("for") {
            trait_name = option::some(first)
            target = self.parse_path()?
        }

        self.parse_where_clause()?
        self.expect_symbol("{")?
        vec[function_decl] methods = vec[function_decl]()
        while !self.eat_symbol("}") {
            methods.push(self.parse_function_decl()?)
        }

        result::ok(impl_decl {
            target: target,
            trait_name: trait_name,
            generics: generics,
            methods: methods,
        })
    }

    func parse_function(mut self, bool require_body) result[parsed_function, parse_error] {
        self.expect_keyword("func")?

        option[named_type] receiver = option::none        if self.at_symbol("(") {
            self.expect_symbol("(")?
            named_type named = self.parse_named_type(vec[string] { ")" })?            self.expect_symbol(")")?
            receiver = option::some(named)
        }
        string name = self.expect_ident()?        vec[string] generics = self.parse_generic_params()?        self.expect_symbol("(")?
        vec[param] params = self.parse_params()?        self.expect_symbol(")")?

        option[string] return_type = option::none        token next = self.peek()?        if !(next.kind == token_kind::symbol && (next.value == "{" || next.value == ";")) && !(
            next.kind == token_kind::keyword && next.value == "where"
        ) {

            return_type = option::some(self.parse_type_text(vec[string] { "where", "{", ";" })?)
        }

        self.parse_where_clause()?

        option[block_expr] body =            if require_body {
                option::some(self.parse_block_expr()?)
            } else {
                option::none
            }

        result::ok(parsed_function {
            sig: function_sig {
                name: name,
                generics: generics,
                params: params,
                return_type: return_type,
            },
            body: body,
            receiver: receiver,
        })
    }

    func parse_params(mut self) result[vec[param], parse_error] {
        vec[param] params = vec[param]()        if self.at_symbol(")") {
            return result::ok(params)
        }

        while true {
            named_type part = self.parse_named_type(vec[string] { ",", ")" })?            params.push(param {
                name: part.name,
                type_name: part.type_name,
            })
            if !self.eat_symbol(",") || self.at_symbol(")") {
                break
            }
        }

        result::ok(params)
    }

    func parse_generic_params(mut self) result[vec[string], parse_error] {
        vec[string] generics = vec[string]()        if !self.eat_symbol("[") {
            return result::ok(generics)
        }

        while !self.eat_symbol("]") {
            string name = self.expect_ident()?            string item =                if self.eat_symbol(":") {
                    vec[string] bounds = vec[string]()                    bounds.push(self.parse_path()?)
                    while self.eat_symbol("+") {
                        bounds.push(self.parse_path()?)
                    }
                    name + ": " + join_strings(bounds, " + ")
                } else {
                    name
                }
            generics.push(item)
            self.eat_symbol(",")
        }

        result::ok(generics)
    }

    func parse_where_clause(mut self) result[(), parse_error] {
        if !self.eat_keyword("where") {
            return result::ok(())
        }
        while true {
            self.parse_type_text(vec[string] { ",", "{", ";" })?
            if !self.eat_symbol(",") || self.at_symbol("{") || self.at_symbol(";") {
                break
            }
        }
        result::ok(())
    }

    func parse_named_type(mut self, vec[string] stop_values) result[named_type, parse_error] {
        vec[token] segment = self.parse_token_segment(stop_values)?        decode_named_type(segment)
    }

    func parse_token_segment(mut self, vec[string] stop_values) result[vec[token], parse_error] {
        vec[token] segment = vec[token]()        int bracket = 0        int paren = 0
        while true {
            token token = self.peek()?            if token.kind == token_kind::eof {
                break
            }
            if bracket == 0 && paren == 0 && contains_string(stop_values, token.value) {
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
            }
            segment.push(self.advance()?)
        }

        result::ok(segment)
    }

    func parse_block_expr(mut self) result[block_expr, parse_error] {
        self.expect_symbol("{")?
        vec[stmt] statements = vec[stmt]()        option[expr] final_expr = option::none
        while !self.at_symbol("}") {
            if self.starts_stmt() {
                statements.push(self.parse_stmt()?)
                continue
            }
            expr expr = self.parse_expr()?            if self.eat_symbol(";") {
                statements.push(stmt::expr(expr_stmt { expr: expr }))
                continue
            }
            if !self.at_symbol("}") {
                statements.push(stmt::expr(expr_stmt { expr: expr }))
                continue
            }
            final_expr = option::some(expr)
            break
        }

        self.expect_symbol("}")?
        result::ok(block_expr {
            statements: statements,
            final_expr: final_expr,
            inferred_type: option::none,
        })
    }

    func starts_stmt(self) bool {
        self.at_keyword("return")
            || self.at_keyword("defer")
            || self.at_keyword("sroutine")
            || self.at_cfor_start()
            || self.looks_like_typed_var_stmt()
            || self.looks_like_increment_stmt()
            || self.looks_like_assignment_stmt()
    }

    func parse_stmt(mut self) result[stmt, parse_error] {
        if self.at_keyword("defer") {
            return result::ok(stmt::defer(self.parse_defer_stmt()?))
        }
        if self.at_keyword("sroutine") {
            return result::ok(stmt::sroutine(self.parse_sroutine_stmt()?))
        }
        if self.at_keyword("return") {
            return result::ok(stmt::return(self.parse_return_stmt()?))
        }
        if self.at_cfor_start() {
            return result::ok(stmt::c_for(self.parse_cfor_stmt()?))
        }
        if self.looks_like_typed_var_stmt() {
            return result::ok(stmt::let(self.parse_typed_var_stmt(true)?))
        }
        if self.looks_like_increment_stmt() {
            return result::ok(stmt::increment(self.parse_increment_stmt(true)?))
        }
        if self.looks_like_assignment_stmt() {
            return result::ok(stmt::assign(self.parse_assign_stmt(true)?))
        }
        result::err(self.error_here("unexpected statement"))
    }

    func parse_var_stmt(mut self, bool consume_semicolon) result[var_stmt, parse_error] {
        result::err(self.error_here("let/var declarations are not supported; use explicit typed declaration"))
    }

    func parse_short_var_stmt(mut self, bool consume_semicolon) result[var_stmt, parse_error] {
        result::err(self.error_here("short declaration := is not supported; use explicit typed declaration"))
    }

    func parse_defer_stmt(mut self) result[defer_stmt, parse_error] {
        self.expect_keyword("defer")?
        expr expr = self.parse_expr()?        self.eat_symbol(";")
        result::ok(defer_stmt { expr: expr })
    }

    func parse_sroutine_stmt(mut self) result[sroutine_stmt, parse_error] {
        self.expect_keyword("sroutine")?
        expr expr = self.parse_expr()?        self.eat_symbol(";")
        result::ok(sroutine_stmt { expr: expr })
    }

    func parse_typed_var_stmt(mut self, bool consume_semicolon) result[var_stmt, parse_error] {
        let segment = self.parse_token_segment(vec[string] { "=" })?
        let named = decode_named_type(segment)?
        self.expect_symbol("=")?
        let value = self.parse_expr()?
        if consume_semicolon {
            self.eat_symbol(";")
        }
        result::ok(var_stmt {
            name: named.name,
            type_name: option::some(named.type_name),
            value: value,
        })
    }

    func parse_assign_stmt(mut self, bool consume_semicolon) result[assign_stmt, parse_error] {
        string name = self.expect_ident()?        self.expect_symbol("=")?
        let value = self.parse_expr()?
        if consume_semicolon {
            self.eat_symbol(";")
        }
        result::ok(assign_stmt {
            name: name,
            value: value,
        })
    }

    func parse_increment_stmt(mut self, bool consume_semicolon) result[increment_stmt, parse_error] {
        string name = self.expect_ident()?        self.expect_symbol("++")?
        if consume_semicolon {
            self.eat_symbol(";")
        }
        result::ok(increment_stmt {
            name: name,
        })
    }

    func parse_cfor_stmt(mut self) result[c_for_stmt, parse_error] {
        self.expect_keyword("for")?
        self.expect_symbol("(")?
        let init = self.parse_for_clause_stmt()?
        self.expect_symbol(";")?
        expr condition = self.parse_expr()?        self.expect_symbol(";")?
        let step = self.parse_for_clause_stmt()?
        self.expect_symbol(")")?
        let body = self.parse_block_expr()?
        result::ok(c_for_stmt {
            init: box(init),
            condition: condition,
            step: box(step),
            body: body,
        })
    }

    func parse_for_clause_stmt(mut self) result[stmt, parse_error] {
        if self.looks_like_typed_var_stmt() {
            return result::ok(stmt::let(self.parse_typed_var_stmt(false)?))
        }
        if self.looks_like_increment_stmt() {
            return result::ok(stmt::increment(self.parse_increment_stmt(false)?))
        }
        if self.looks_like_assignment_stmt() {
            return result::ok(stmt::assign(self.parse_assign_stmt(false)?))
        }
        result::err(self.error_here("unexpected for clause"))
    }

    func parse_return_stmt(mut self) result[return_stmt, parse_error] {
        self.expect_keyword("return")?
        if self.eat_symbol(";") {
            return result::ok(return_stmt {
                value: option::none,
            })
        }
        let value = self.parse_expr()?
        self.eat_symbol(";")
        result::ok(return_stmt {
            value: option::some(value),
        })
    }

    func parse_expr(mut self) result[expr, parse_error] {
        if self.at_keyword("select") {
            return self.parse_select_expr()
        }
        if self.at_keyword("switch") {
            return self.parse_switch_expr()
        }
        if self.at_keyword("if") {
            return self.parse_if_expr()
        }
        if self.at_keyword("while") {
            return self.parse_while_expr()
        }
        if self.at_keyword("for") {
            return self.parse_for_expr()
        }
        self.parse_binary_expr(0)
    }

    func parse_select_expr(mut self) result[expr, parse_error] {
        self.expect_keyword("select")?
        self.expect_symbol("{")?

        string mode = ""        vec[expr] recv_args = vec[expr]()        vec[expr] send_args = vec[expr]()        option[expr] timeout_arg = option[expr].none        bool has_default = false
        while !self.eat_symbol("}") {
            self.expect_keyword("case")?
            if self.eat_keyword("default") {
                if has_default {
                    return result::err(self.error_here("duplicate default case in select"))
                }
                has_default = true
                self.expect_symbol(":")?
                self.eat_symbol(";")
                continue
            }

            let case_expr = self.parse_expr()?
            self.expect_symbol(":")?
            self.eat_symbol(";")

            switch case_expr {
                expr.call(call_value) : {
                    switch call_value.callee.value {
                        expr.name(name_value) : {
                            if name_value.name == "recv" {
                                if mode != "" && mode != "recv" {
                                    return result::err(self.error_here("select cannot mix recv and send cases"))
                                }
                                mode = "recv"
                                if call_value.args.len() == 0 {
                                    return result::err(self.error_here("select recv case requires at least one channel"))
                                }
                                int ri = 0                                while ri < call_value.args.len() {
                                    recv_args.push(call_value.args[ri])
                                    ri = ri + 1
                                }
                            } else if name_value.name == "send" {
                                if mode != "" && mode != "send" {
                                    return result::err(self.error_here("select cannot mix recv and send cases"))
                                }
                                mode = "send"
                                if call_value.args.len() < 2 || (call_value.args.len() % 2) != 0 {
                                    return result::err(self.error_here("select send case expects channel/value pairs"))
                                }
                                int si = 0                                while si < call_value.args.len() {
                                    send_args.push(call_value.args[si])
                                    si = si + 1
                                }
                            } else if name_value.name == "timeout" || name_value.name == "after" {
                                if timeout_arg.is_some() {
                                    return result::err(self.error_here("duplicate timeout case in select"))
                                }
                                if call_value.args.len() != 1 {
                                    return result::err(self.error_here("select timeout case expects one tick argument"))
                                }
                                timeout_arg = option[expr].some(call_value.args[0])
                            } else {
                                return result::err(self.error_here("unsupported select case expression"))
                            }
                        }
                        _ : return result::err(self.error_here("select case must be recv/send/timeout call")),
                    }
                }
                _ : return result::err(self.error_here("select case must be call expression")),
            }
        }

        if timeout_arg.is_some() && has_default {
            return result::err(self.error_here("select cannot combine timeout and default"))
        }
        if mode == "" {
            return result::err(self.error_here("select requires recv(...) or send(...) case"))
        }

        string callee_name = ""        vec[expr] args = vec[expr]()        if mode == "recv" {
            if recv_args.len() == 0 {
                return result::err(self.error_here("select recv requires at least one channel"))
            }
            callee_name = "select_recv"
            int ri = 0            while ri < recv_args.len() {
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
                return result::err(self.error_here("select send requires channel/value pairs"))
            }
            callee_name = "select_send"
            int si = 0            while si < send_args.len() {
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

        result::ok(build_call_expr(callee_name, args))
    }

    func parse_switch_expr(mut self) result[expr, parse_error] {
        self.expect_keyword("switch")?
        expr subject = self.parse_expr()?        self.expect_symbol("{")?
        vec[switch_arm] arms = vec[switch_arm]()
        while !self.eat_symbol("}") {
            let pattern = self.parse_pattern()?
            self.expect_symbol(":")?
            expr expr = self.parse_expr()?            arms.push(switch_arm {
                pattern: pattern,
                expr: expr,
            })
            self.eat_symbol(",")
        }

        result::ok(expr::switch(switch_expr {
            subject: box(subject),
            arms: arms,
            inferred_type: option::none,
        }))
    }

    func parse_if_expr(mut self) result[expr, parse_error] {
        self.expect_keyword("if")?
        expr condition = self.parse_expr()?        block_expr then_branch = self.parse_block_expr()?        option[box[expr]] else_branch =            if self.eat_keyword("else") {
                if self.at_keyword("if") {
                    option::some(box(self.parse_if_expr()?))
                } else {
                    option::some(box(expr::block(self.parse_block_expr()?)))
                }
            } else {
                option::none
            }

        result::ok(expr::if(if_expr {
            condition: box(condition),
            then_branch: then_branch,
            else_branch: else_branch,
            inferred_type: option::none,
        }))
    }

    func parse_while_expr(mut self) result[expr, parse_error] {
        self.expect_keyword("while")?
        expr condition = self.parse_expr()?        let body = self.parse_block_expr()?
        result::ok(expr::while(while_expr {
            condition: box(condition),
            body: body,
            inferred_type: option::none,
        }))
    }

    func parse_for_expr(mut self) result[expr, parse_error] {
        self.expect_keyword("for")?
        string name = self.expect_ident()?        self.expect_keyword("in")?
        expr iterable = self.parse_expr()?        let body = self.parse_block_expr()?
        result::ok(expr::for(for_expr {
            name: name,
            iterable: box(iterable),
            body: body,
            inferred_type: option::none,
        }))
    }

    func parse_pattern(mut self) result[pattern, parse_error] {
        if self.eat_ident_value("_") {
            return result::ok(pattern::wildcard(wildcard_pattern {}))
        }

        token token = self.peek()?        if token.kind == token_kind::int {
            self.advance()?
            return result::ok(pattern::literal(literal_pattern {
                value: expr::int(int_expr {
                    value: token.value,
                    inferred_type: option::none,
                }),
            }))
        }
        if token.kind == token_kind::string {
            self.advance()?
            return result::ok(pattern::literal(literal_pattern {
                value: expr::string(string_expr {
                    value: token.value,
                    inferred_type: option::none,
                }),
            }))
        }
        if self.at_keyword("true") {
            self.advance()?
            return result::ok(pattern::literal(literal_pattern {
                value: expr::bool(bool_expr {
                    value: true,
                    inferred_type: option::none,
                }),
            }))
        }
        if self.at_keyword("false") {
            self.advance()?
            return result::ok(pattern::literal(literal_pattern {
                value: expr::bool(bool_expr {
                    value: false,
                    inferred_type: option::none,
                }),
            }))
        }

        string path = self.parse_path()?        if self.eat_symbol("(") {
            vec[pattern] args = vec[pattern]()            if !self.at_symbol(")") {
                while true {
                    args.push(self.parse_pattern()?)
                    if !self.eat_symbol(",") || self.at_symbol(")") {
                        break
                    }
                }
            }
            self.expect_symbol(")")?
            return result::ok(pattern::variant(variant_pattern {
                path: path,
                args: args,
            }))
        }

        if path_contains_dot(path) || starts_with_upper(path) {
            return result::ok(pattern::variant(variant_pattern {
                path: path,
                args: vec[pattern](),
            }))
        }

        result::ok(pattern::name(name_pattern { name: path }))
    }

    func parse_binary_expr(mut self, int min_precedence) result[expr, parse_error] {
        let expr = self.parse_unary_expr()?
        while true {
            token token = self.peek()?            int precedence = self.binary_precedence(token.value)            if precedence < min_precedence {
                break
            }
            string op = self.advance()?.value            let rhs = self.parse_binary_expr(precedence + 1)?
            expr = expr::binary(binary_expr {
                left: box(expr),
                op: op,
                right: box(rhs),
                inferred_type: option::none,
            })
        }
        result::ok(expr)
    }

    func parse_unary_expr(mut self) result[expr, parse_error] {
        if self.eat_symbol("&") {
            bool mutable = self.eat_keyword("mut")            let target = self.parse_unary_expr()?
            return result::ok(expr::borrow(borrow_expr {
                target: box(target),
                mutable: mutable,
                inferred_type: option::none,
            }))
        }
        self.parse_call_expr()
    }

    func parse_call_expr(mut self) result[expr, parse_error] {
        let expr = self.parse_primary_expr()?
        while true {
            if self.eat_symbol("(") {
                vec[expr] args = vec[expr]()                if !self.at_symbol(")") {
                    while true {
                        args.push(self.parse_expr()?)
                        if !self.eat_symbol(",") || self.at_symbol(")") {
                            break
                        }
                    }
                }
                self.expect_symbol(")")?
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
                    member: self.expect_ident()?,
                    inferred_type: option::none,
                })
                continue
            }
            if self.eat_symbol(":") {
                self.expect_symbol(":")?
                expr = expr::member(member_expr {
                    target: box(expr),
                    member: self.expect_ident()?,
                    inferred_type: option::none,
                })
                continue
            }
            if self.eat_symbol("[") {
                let index = self.parse_expr()?
                self.expect_symbol("]")?
                expr = expr::index(index_expr {
                    target: box(expr),
                    index: box(index),
                    inferred_type: option::none,
                })
                continue
            }
            break
        }
        result::ok(expr)
    }

    func parse_primary_expr(mut self) result[expr, parse_error] {
        token token = self.peek()?        if token.kind == token_kind::int {
            self.advance()?
            return result::ok(expr::int(int_expr {
                value: token.value,
                inferred_type: option::none,
            }))
        }
        if token.kind == token_kind::string {
            self.advance()?
            return result::ok(expr::string(string_expr {
                value: token.value,
                inferred_type: option::none,
            }))
        }
        if self.at_keyword("true") {
            self.advance()?
            return result::ok(expr::bool(bool_expr {
                value: true,
                inferred_type: option::none,
            }))
        }
        if self.at_keyword("false") {
            self.advance()?
            return result::ok(expr::bool(bool_expr {
                value: false,
                inferred_type: option::none,
            }))
        }
        if self.at_keyword("nil") {
            self.advance()?
            return result::ok(expr::name(name_expr {
                name: "nil",
                inferred_type: option::none,
            }))
        }
        if self.at_symbol("{") {
            return result::ok(expr::block(self.parse_block_expr()?))
        }
        if self.eat_symbol("(") {
            expr expr = self.parse_expr()?            self.expect_symbol(")")?
            return result::ok(expr)
        }

        if self.at_symbol("[") {

            let bracket = self.parse_bracket_group()?
            let type_text = bracket

            token token = self.peek().unwrap()            if token.kind != token_kind::symbol || token.value != "{" {
                let seg = self.parse_token_segment(vec[string] { "{" })?
                type_text = type_text + " " + join_token_values(seg)
            }
            self.expect_symbol("{")?
            vec[expr] items = vec[expr]()            if !self.at_symbol("}") {
                while true {
                    items.push(self.parse_expr()?)
                    if !self.eat_symbol(",") || self.at_symbol("}") {
                        break
                    }
                }
            }
            self.expect_symbol("}")?
            return result::ok(expr::array(array_literal { type_text: option::some(type_text.trim()), items: items }))
        }

        if token.kind == token_kind::ident && token.value == "map" {

            self.advance()?
            let bracket = self.parse_bracket_group()?
            let type_text = "map" + bracket

            let token2 = self.peek().unwrap()
            if token2.kind == token_kind::ident || token2.kind == token_kind::symbol {
                let seg = self.parse_token_segment(vec[string] { "{" })?
                type_text = type_text + " " + join_token_values(seg)
            }
            self.expect_symbol("{")?
            vec[map_entry] entries = vec[map_entry]()            if !self.at_symbol("}") {
                while true {
                    let key = self.parse_expr()?
                    self.expect_symbol(":")?
                    let value = self.parse_expr()?
                    entries.push(map_entry { key: key, value: value })
                    if !self.eat_symbol(",") || self.at_symbol("}") {
                        break
                    }
                }
            }
            self.expect_symbol("}")?
            return result::ok(expr::map(map_literal { type_text: option::some(type_text.trim()), entries: entries }))
        }
        result::ok(expr::name(name_expr {
            name: self.expect_ident()?,
            inferred_type: option::none,
        }))
    }

    func binary_precedence(self, string op) int {
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

    func parse_use_path(mut self) result[string, parse_error] {
        vec[string] parts = vec[string]()        parts.push(self.expect_ident()?)
        while self.eat_symbol(".") {
            if self.eat_symbol("{") {
                vec[string] members = vec[string]()                while !self.eat_symbol("}") {
                    let member = self.expect_ident()?
                    string text =                        if self.eat_keyword("as") {
                            member + " as " + self.expect_ident()?
                        } else {
                            member
                        }
                    members.push(text)
                    self.eat_symbol(",")
                }
                return result::ok(join_strings(parts, ".") + ".{" + join_strings(members, ", ") + "}")
            }
            parts.push(self.expect_ident()?)
        }
        result::ok(join_strings(parts, "."))
    }

    func parse_path(mut self) result[string, parse_error] {
        vec[string] parts = vec[string]()        parts.push(self.expect_ident()?)
        while self.eat_symbol(".") {
            parts.push(self.expect_ident()?)
        }
        while self.at_symbol(":") && self.peek_at(1).unwrap().kind == token_kind::symbol && self.peek_at(1).unwrap().value == ":" {
            self.expect_symbol(":")?
            self.expect_symbol(":")?
            parts.push(self.expect_ident()?)
        }
        if self.at_symbol("[") {
            let last = parts.pop().unwrap()
            parts.push(last + self.parse_bracket_group()?)
        }
        result::ok(join_strings(parts, "."))
    }

    func parse_type_text(mut self, vec[string] stop_values) result[string, parse_error] {
        vec[string] parts = vec[string]()        int bracket = 0        int paren = 0
        while true {
            token token = self.peek()?            if token.kind == token_kind::eof {
                break
            }
            if bracket == 0 && paren == 0 && contains_string(stop_values, token.value) {
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
            }
            parts.push(self.advance()?.value)
        }

        result::ok(normalize_type_text(join_strings(parts, " ")))
    }

    func parse_bracket_group(mut self) result[string, parse_error] {
        vec[string] parts = vec[string]()        parts.push(self.advance()?.value)
        int depth = 1        while depth > 0 {
            token token = self.advance()?            parts.push(token.value)
            if token.value == "[" {
                depth = depth + 1
            } else if token.value == "]" {
                depth = depth - 1
            }
        }
        result::ok(
            join_strings(parts, " ")
                .replace("[ ", "[")
                .replace(" ]", "]")
                .replace(" ,", ",")
        )
    }

    func at(self, token_kind kind) bool {
        self.peek().unwrap().kind == kind
    }

    func at_keyword(self, string value) bool {
        token token = self.peek().unwrap()        token.kind == token_kind::keyword && token.value == value
    }

    func at_symbol(self, string value) bool {
        token token = self.peek().unwrap()        token.kind == token_kind::symbol && token.value == value
    }

    func at_symbol_after_keyword(self, string value) bool {
        token first = self.peek().unwrap()        if first.kind != token_kind::keyword {
            return false
        }
        token second = self.peek_at(1).unwrap()        second.kind == token_kind::symbol && second.value == value
    }

    func at_cfor_start(self) bool {
        self.at_keyword("for") && self.peek_at(1).unwrap().kind == token_kind::symbol && self.peek_at(1).unwrap().value == "("
    }

    func looks_like_assignment_stmt(self) bool {
        token first = self.peek().unwrap()        token second = self.peek_at(1).unwrap()        first.kind == token_kind::ident && second.kind == token_kind::symbol && second.value == "="
    }

    func looks_like_short_var_stmt(self) bool {
        false
    }

    func looks_like_increment_stmt(self) bool {
        token first = self.peek().unwrap()        token second = self.peek_at(1).unwrap()        first.kind == token_kind::ident && second.kind == token_kind::symbol && second.value == "++"
    }

    func looks_like_typed_var_stmt(self) bool {
        int offset = self.find_top_level_symbol_offset("=")        if offset <= 0 {
            return false
        }
        decode_named_type(slice_tokens(self.tokens, self.index, self.index + offset)).is_ok()
    }

    func eat_keyword(mut self, string value) bool {
        if self.at_keyword(value) {
            self.advance().unwrap()
            return true
        }
        false
    }

    func eat_ident_value(mut self, string value) bool {
        token token = self.peek().unwrap()        if token.kind == token_kind::ident && token.value == value {
            self.advance().unwrap()
            return true
        }
        false
    }

    func eat_symbol(mut self, string value) bool {
        if self.at_symbol(value) {
            self.advance().unwrap()
            return true
        }
        false
    }

    func expect_keyword(mut self, string value) result[token, parse_error] {
        token token = self.peek()?        if token.kind == token_kind::keyword && token.value == value {
            return self.advance()
        }
        result::err(parse_error {
            message: "expected keyword " + value,
            line: token.line,
            column: token.column,
        })
    }

    func expect_symbol(mut self, string value) result[token, parse_error] {
        token token = self.peek()?        if token.kind == token_kind::symbol && token.value == value {
            return self.advance()
        }
        result::err(parse_error {
            message: "expected symbol " + value,
            line: token.line,
            column: token.column,
        })
    }

    func expect_ident(mut self) result[string, parse_error] {
        token token = self.peek()?        if token.kind == token_kind::ident {
            self.advance()?
            return result::ok(token.value)
        }
        if token.kind == token_kind::keyword && token.value == "self" {
            self.advance()?
            return result::ok(token.value)
        }
        result::err(parse_error {
            message: "expected identifier",
            line: token.line,
            column: token.column,
        })
    }

    func peek(self) result[token, parse_error] {
        self.peek_at(0)
    }

    func peek_at(self, int offset) result[token, parse_error] {
        if self.index >= len(self.tokens) {
            return result::err(parse_error {
                message: "unexpected eof",
                line: 0,
                column: 0,
            })
        }
        int target = self.index + offset        if target >= len(self.tokens) {
            target = len(self.tokens) - 1
        }
        result::ok(self.tokens[target])
    }

    func advance(mut self) result[token, parse_error] {
        token token = self.peek()?        self.index = self.index + 1
        result::ok(token)
    }

    func error_here(self, string message) parse_error {
        token token = self.peek().unwrap()        parse_error {
            message: message,
            line: token.line,
            column: token.column,
        }
    }
}

impl parser {
    func find_top_level_symbol_offset(self, string value) int {
        int bracket = 0        int paren = 0        int offset = 0        while self.index + offset < len(self.tokens) {
            let token = self.tokens[self.index + offset]
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

func decode_named_type(vec[token] tokens) result[named_type, parse_error] {
    int colon = find_token_value(tokens, ":")    if colon >= 0 {
        let name_tokens = slice_tokens(tokens, 0, colon)
        let type_tokens = slice_tokens(tokens, colon + 1, len(tokens))
        return result::ok(named_type {
            name: normalize_type_text(join_token_values(name_tokens)),
            type_name: normalize_type_text(join_token_values(type_tokens)),
        })
    }

    int split = find_decl_name_index(tokens)    if split <= 0 {
        return result::err(parse_error {
            message: "expected typed name",
            line: 0,
            column: 0,
        })
    }
    result::ok(named_type {
        name: tokens[split].value,
        type_name: normalize_type_text(join_token_values(slice_tokens(tokens, 0, split))),
    })
}

func slice_tokens(vec[token] tokens, int start, int end) vec[token] {
    vec[token] out = vec[token]()    int i = start    while i < end {
        out.push(tokens[i])
        i = i + 1
    }
    out
}

func join_token_values(vec[token] tokens) string {
    vec[string] parts = vec[string]()    for token in tokens {
        parts.push(token.value)
    }
    join_strings(parts, " ")
}

func find_token_value(vec[token] tokens, string value) int {
    int bracket = 0    int paren = 0    int i = 0    while i < len(tokens) {
        let token = tokens[i]
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
    int bracket = 0    int paren = 0    int index = -1    int i = 0    while i < len(tokens) {
        let token = tokens[i]
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
        .replace("& mut ", "&mut ")
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
    string out = ""    bool first = true    for value in values {
        if !first {
            out = out + sep
        }
        out = out + value
        first = false
    }
    out
}

func path_contains_dot(string path) bool {
    int i = 0    while i < len(path) {
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
    string ch = char_at(text, 0)    switch ch {
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
