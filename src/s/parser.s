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
        result::ok(tokens) : parse_tokens(tokens),
        result::err(err) : result::err(parse_error {
            message: err.message,
            line: err.line,
            column: err.column,
        }),
    }
}

func parse_tokens(vec[token] tokens) (source_file, parse_error) {
    parser parser = parser {        tokens: tokens,
        index: 0,
    }
    parser.parse_source_file()
}
    int global_parse_depth = 0    func log_depth(string msg) {
        print(msg)
    }

func (parser* self) parse_source_file() (source_file, parse_error) {
        global_parse_depth = global_parse_depth + 1
        log_depth("parse_source_file depth: " + to_string(global_parse_depth))
        self.expect_keyword("package")?
        string pkg = self.parse_path()?        vec[use_decl] uses = vec[use_decl]()        vec[item] items = vec[item]()
        for self.at_keyword("use") {
            uses.push(self.parse_use_decl()?)
        }
        for !self.at(token_kind::eof) {
            if self.at_keyword("const") && self.at_symbol_after_keyword("(") {
                vec[const_decl] consts = self.parse_const_group_items()?                int ci = 0                for ci < consts.len() {
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

func (parser* self) parse_use_decl() (use_decl, parse_error) {
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

func (parser* self) parse_item() (item, parse_error) {
        if self.at_keyword("func") {
            parsed_function parsed = self.parse_function(true)?
            switch parsed.receiver {
                option::some(r) : {
                    function_decl method = function_decl {                        sig: parsed.sig,
                        body: parsed.body,
                        is_public: starts_with_upper(parsed.sig.name),
                    }
                    return result::ok(item::method(receiver_method_decl {
                        receiver_name: r.name,
                        receiver_type: r.type_name,
                        method: method,
                    }))
                },
                option::none : {
                    return result::ok(item::function(parsed))
                }
            }
        }
        if self.at_keyword("const") {
            return result::ok(item::const(self.parse_const_decl()?))
        }
        if self.at_keyword("var") {
            return result::ok(item::var(self.parse_var_decl()?))
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
        result::err(self.error_here("unexpected token"))
    }

func (parser* self) parse_const_decl() (const_decl, parse_error) {
        self.expect_keyword("const")?
        const_decl entry = self.parse_const_entry(false, 0)?        self.eat_symbol(";")
        result::ok(entry)
    }

func (parser* self) parse_const_group_items() (vec[const_decl], parse_error) {
        self.expect_keyword("const")?
        self.expect_symbol("(")?
        vec[const_decl] out = vec[const_decl]()        int iota_index = 0        for !self.eat_symbol(")") {
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

func (parser* self) parse_const_entry(bool allow_omitted_value, int iota_index) (const_decl, parse_error) {
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

func (parser* self) parse_var_decl() (var_decl, parse_error) {
        self.expect_keyword("var")?
        string name = self.expect_ident()?
        option[string] type_name = option::none
        option[expr] value = option::none

        if !self.at_symbol("=") && !self.at_symbol(";") {
            type_name = option::some(self.parse_type_expr()?)
        }

        if self.eat_symbol("=") {
            value = option::some(self.parse_expr()?)
        }

        self.eat_symbol(";")

        result::ok(var_decl {
            name: name,
            type_name: type_name,
            value: value,
        })
    }

func (parser* self) parse_function_decl() (function_decl, parse_error) {
        parsed_function pair = self.parse_function(true)?        if pair.receiver.is_some() {
            return result::err(self.error_here("method receiver not allowed in this context"))
        }
        result::ok(function_decl {
            sig: pair.sig,
            body: pair.body,
            is_public: starts_with_upper(pair.sig.name),
        })
    }

func (parser* self) parse_struct_decl() (struct_decl, parse_error) {
        self.expect_keyword("struct")?
        string name = self.expect_ident()?        vec[string] generics = self.parse_generic_params()?        self.expect_symbol("{")?
        vec[field] fields = vec[field]()
        for !self.eat_symbol("}") {
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

func (parser* self) parse_enum_decl() (enum_decl, parse_error) {
        self.expect_keyword("enum")?
        string name = self.expect_ident()?        vec[string] generics = self.parse_generic_params()?        self.expect_symbol("{")?
        vec[enum_variant] variants = vec[enum_variant]()
        for !self.eat_symbol("}") {
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

func (parser* self) parse_trait_decl() (trait_decl, parse_error) {
        self.expect_keyword("trait")?
        string name = self.expect_ident()?        vec[string] generics = self.parse_generic_params()?        self.expect_symbol("{")?
        vec[function_sig] methods = vec[function_sig]()
        for !self.eat_symbol("}") {
            pair := self.parse_function(false)?
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

func (parser* self) parse_function(bool require_body) (parsed_function, parse_error) {
        self.expect_keyword("func")?
        option[named_type] receiver = option::none        if self.at_symbol("(") {
            self.expect_symbol("(")?
            receiver_tokens := self.parse_token_segment(vec[string] { ")" })?
            named_type named = decode_receiver_type(receiver_tokens)?
            self.expect_symbol(")")?
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

func (parser* self) parse_params() (vec[param], parse_error) {
        vec[param] params = vec[param]()        if self.at_symbol(")") {
            return result::ok(params)
        }
        for true {
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

func (parser* self) parse_generic_params() (vec[string], parse_error) {
        vec[string] generics = vec[string]()        if !self.eat_symbol("[") {
            return result::ok(generics)
        }
        for !self.eat_symbol("]") {
            string name = self.expect_ident()?            string item =                if self.eat_symbol(":") {
                    vec[string] bounds = vec[string]()                    bounds.push(self.parse_path()?)
                    for self.eat_symbol("+") {
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

func (parser* self) parse_where_clause() ((), parse_error) {
        if !self.eat_keyword("where") {
            return result::ok(())
        }
        for true {
            self.parse_type_text(vec[string] { ",", "{", ";" })?
            if !self.eat_symbol(",") || self.at_symbol("{") || self.at_symbol(";") {
                break
            }
        }
        result::ok(())
    }

func (parser* self) parse_named_type(vec[string] stop_values) (named_type, parse_error) {
        vec[token] segment = self.parse_token_segment(stop_values)?        decode_named_type(segment)
    }

func (parser* self) parse_token_segment(vec[string] stop_values) (vec[token], parse_error) {
        vec[token] segment = vec[token]()        int bracket = 0        int paren = 0
        for true {
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

func (parser* self) parse_block_expr() (block_expr, parse_error) {
        self.expect_symbol("{")?
        vec[stmt] statements = vec[stmt]()        option[expr] final_expr = option::none
        for !self.at_symbol("}") {
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

func (parser* self) parse_var_stmt(bool consume_semicolon) (var_stmt, parse_error) {
        result::err(self.error_here("let/var declarations are not supported; use explicit typed declaration"))
    }

func (parser* self) parse_short_var_stmt(bool consume_semicolon) (var_stmt, parse_error) {
        result::err(self.error_here("short declaration := is not supported; use explicit typed declaration"))
    }

func (parser* self) parse_defer_stmt() (defer_stmt, parse_error) {
        self.expect_keyword("defer")?
        expr expr = self.parse_expr()?        self.eat_symbol(";")
        result::ok(defer_stmt { expr: expr })
    }

func (parser* self) parse_sroutine_stmt() (sroutine_stmt, parse_error) {
        self.expect_keyword("sroutine")?
        expr expr = self.parse_expr()?        self.eat_symbol(";")
        result::ok(sroutine_stmt { expr: expr })
    }

func (parser* self) parse_typed_var_stmt(bool consume_semicolon) (var_stmt, parse_error) {
        segment := self.parse_token_segment(vec[string] { "=" })?
        named := decode_named_type(segment)?
        self.expect_symbol("=")?
        value := self.parse_expr()?
        if consume_semicolon {
            self.eat_symbol(";")
        }
        result::ok(var_stmt {
            name: named.name,
            type_name: option::some(named.type_name),
            value: value,
        })
    }

func (parser* self) parse_assign_stmt(bool consume_semicolon) (assign_stmt, parse_error) {
        string name = self.expect_ident()?        self.expect_symbol("=")?
        value := self.parse_expr()?
        if consume_semicolon {
            self.eat_symbol(";")
        }
        result::ok(assign_stmt {
            name: name,
            value: value,
        })
    }

func (parser* self) parse_increment_stmt(bool consume_semicolon) (increment_stmt, parse_error) {
        string name = self.expect_ident()?        self.expect_symbol("++")?
        if consume_semicolon {
            self.eat_symbol(";")
        }
        result::ok(increment_stmt {
            name: name,
        })
    }

func (parser* self) parse_cfor_stmt() (c_for_stmt, parse_error) {
        self.expect_keyword("for")?
        self.expect_symbol("(")?
        init := self.parse_for_clause_stmt()?
        self.expect_symbol(";")?
        expr condition = self.parse_expr()?        self.expect_symbol(";")?
        step := self.parse_for_clause_stmt()?
        self.expect_symbol(")")?
        body := self.parse_block_expr()?
        result::ok(c_for_stmt {
            init: box(init),
            condition: condition,
            step: box(step),
            body: body,
        })
    }

func (parser* self) parse_for_clause_stmt() (stmt, parse_error) {
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

func (parser* self) parse_return_stmt() (return_stmt, parse_error) {
        self.expect_keyword("return")?
        if self.eat_symbol(";") {
            return result::ok(return_stmt {
                value: option::none,
            })
        }
        value := self.parse_expr()?
        self.eat_symbol(";")
        result::ok(return_stmt {
            value: option::some(value),
        })
    }

func (parser* self) parse_expr() (expr, parse_error) {
        if self.at_keyword("select") {
            return self.parse_select_expr()
        }
        if self.at_keyword("switch") {
            return self.parse_switch_expr()
        }
        if self.at_keyword("if") {
            return self.parse_if_expr()
        }
        if self.at_keyword("for") {
            return self.parse_for_expr()
        }
        self.parse_binary_expr(0)
    }

func (parser* self) parse_select_expr() (expr, parse_error) {
        self.expect_keyword("select")?
        self.expect_symbol("{")?
        string mode = ""        vec[expr] recv_args = vec[expr]()        vec[expr] send_args = vec[expr]()        option[expr] timeout_arg = option[expr].none        bool has_default = false
        for !self.eat_symbol("}") {
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
            case_expr := self.parse_expr()?
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
                                int ri = 0                                for ri < call_value.args.len() {
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
                                int si = 0                                for si < call_value.args.len() {
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
            int ri = 0            for ri < recv_args.len() {
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
            int si = 0            for si < send_args.len() {
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

func (parser* self) parse_switch_expr() (expr, parse_error) {
        self.expect_keyword("switch")?
        expr subject = self.parse_expr()?        self.expect_symbol("{")?
        vec[switch_arm] arms = vec[switch_arm]()
        for !self.eat_symbol("}") {
            pattern := self.parse_pattern()?
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

func (parser* self) parse_if_expr() (expr, parse_error) {
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

func (parser* self) parse_for_expr() (expr, parse_error) {
        self.expect_keyword("for")?
        
        if self.at_symbol("{") {
            body := self.parse_block_expr()?
            return result::ok(expr::for(for_expr {
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
            self.expect_symbol("(")?
            init := self.parse_for_clause_stmt()?
            self.expect_symbol(";")?
            expr condition = self.parse_expr()?            self.expect_symbol(";")?
            post := self.parse_for_clause_stmt()?
            self.expect_symbol(")")?
            body := self.parse_block_expr()?
            return result::ok(expr::for(for_expr {
                init: option::some(box(init)),
                condition: option::some(box(condition)),
                post: option::some(box(post)),
                names: vec[string](),
                iterable: option::none,
                body: body,
                inferred_type: option::none,
            }))
        }
        
        token token = self.peek()?        if token.kind == token_kind::ident && self.at_symbol_after_keyword("in") {
            string name = self.expect_ident()?            self.expect_keyword("in")?
            expr iterable = self.parse_expr()?            body := self.parse_block_expr()?
            return result::ok(expr::for(for_expr {
                init: option::none,
                condition: option::none,
                post: option::none,
                names: vec[string] { name },
                iterable: option::some(box(iterable)),
                body: body,
                inferred_type: option::none,
            }))
        }
        
        expr condition = self.parse_expr()?        body := self.parse_block_expr()?
        result::ok(expr::for(for_expr {
            init: option::none,
            condition: option::some(box(condition)),
            post: option::none,
            names: vec[string](),
            iterable: option::none,
            body: body,
            inferred_type: option::none,
        }))
    }

func (parser* self) parse_pattern() (pattern, parse_error) {
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
                for true {
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

func (parser* self) parse_binary_expr(int min_precedence) (expr, parse_error) {
        expr := self.parse_unary_expr()?
        for true {
            token token = self.peek()?            int precedence = self.binary_precedence(token.value)            if precedence < min_precedence {
                break
            }
            string op = self.advance()?.value            rhs := self.parse_binary_expr(precedence + 1)?
            expr = expr::binary(binary_expr {
                left: box(expr),
                op: op,
                right: box(rhs),
                inferred_type: option::none,
            })
        }
        result::ok(expr)
    }

func (parser* self) parse_unary_expr() (expr, parse_error) {
        if self.eat_symbol("&") {
            bool mutable = false
            target := self.parse_unary_expr()?
            return result::ok(expr::borrow(borrow_expr {
                target: box(target),
                mutable: mutable,
                inferred_type: option::none,
            }))
        }
        self.parse_call_expr()
    }

func (parser* self) parse_call_expr() (expr, parse_error) {
        expr := self.parse_primary_expr()?
        for true {
            if self.eat_symbol("(") {
                vec[expr] args = vec[expr]()                if !self.at_symbol(")") {
                    for true {
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
                index := self.parse_expr()?
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

func (parser* self) parse_primary_expr() (expr, parse_error) {
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
            bracket := self.parse_bracket_group()?
            type_text := bracket
            token token = self.peek().unwrap()            if token.kind != token_kind::symbol || token.value != "{" {
                seg := self.parse_token_segment(vec[string] { "{" })?
                type_text = type_text + " " + join_token_values(seg)
            }
            self.expect_symbol("{")?
            vec[expr] items = vec[expr]()            if !self.at_symbol("}") {
                for true {
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
            bracket := self.parse_bracket_group()?
            type_text := "map" + bracket
            token2 := self.peek().unwrap()
            if token2.kind == token_kind::ident || token2.kind == token_kind::symbol {
                seg := self.parse_token_segment(vec[string] { "{" })?
                type_text = type_text + " " + join_token_values(seg)
            }
            self.expect_symbol("{")?
            vec[map_entry] entries = vec[map_entry]()            if !self.at_symbol("}") {
                for true {
                    key := self.parse_expr()?
                    self.expect_symbol(":")?
                    value := self.parse_expr()?
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
        vec[string] parts = vec[string]()        parts.push(self.expect_ident()?)
        for self.eat_symbol(".") {
            if self.eat_symbol("{") {
                vec[string] members = vec[string]()                for !self.eat_symbol("}") {
                    member := self.expect_ident()?
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

func (parser* self) parse_path() (string, parse_error) {
        vec[string] parts = vec[string]()        parts.push(self.expect_ident()?)
        for self.eat_symbol(".") {
            parts.push(self.expect_ident()?)
        }
        for self.at_symbol(":") && self.peek_at(1).unwrap().kind == token_kind::symbol && self.peek_at(1).unwrap().value == ":" {
            self.expect_symbol(":")?
            self.expect_symbol(":")?
            parts.push(self.expect_ident()?)
        }
        if self.at_symbol("[") {
            last := parts.pop().unwrap()
            parts.push(last + self.parse_bracket_group()?)
        }
        result::ok(join_strings(parts, "."))
    }

func (parser* self) parse_type_text(vec[string] stop_values) (string, parse_error) {
        vec[string] parts = vec[string]()        int bracket = 0        int paren = 0
        for true {
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

func (parser* self) parse_bracket_group() (string, parse_error) {
        vec[string] parts = vec[string]()        parts.push(self.advance()?.value)
        int depth = 1        for depth > 0 {
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
        token token = self.peek()?        if token.kind == token_kind::keyword && token.value == value {
            return self.advance()
        }
        result::err(parse_error {
            message: "expected keyword " + value,
            line: token.line,
            column: token.column,
        })
    }

func (parser* self) expect_symbol(string value) (token, parse_error) {
        token token = self.peek()?        if token.kind == token_kind::symbol && token.value == value {
            return self.advance()
        }
        result::err(parse_error {
            message: "expected symbol " + value,
            line: token.line,
            column: token.column,
        })
    }

func (parser* self) expect_ident() (string, parse_error) {
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

func (parser* self) peek() (token, parse_error) {
        self.peek_at(0)
    }

func (parser* self) peek_at(int offset) (token, parse_error) {
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

func (parser* self) advance() (token, parse_error) {
        token token = self.peek()?        self.index = self.index + 1
        result::ok(token)
    }

func (parser* self) error_here(string message) parse_error {
        token token = self.peek().unwrap()        parse_error {
            message: message,
            line: token.line,
            column: token.column,
        }
    }

func (parser* self) find_top_level_symbol_offset(string value) int {
        int bracket = 0        int paren = 0        int offset = 0        for self.index + offset < len(self.tokens) {
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
        return decode_named_type(tokens)
    }
    if tokens.len() >= 2 && tokens[0].kind == token_kind::ident {
        return result::ok(named_type {
            name: tokens[0].value,
            type_name: normalize_type_text(join_token_values(slice_tokens(tokens, 1, len(tokens)))),
        })
    }
    result::err(parse_error {
        message: "expected receiver in '(name Type)' or '(name: Type)' form",
        line: 0,
        column: 0,
    })
}

func decode_named_type(vec[token] tokens) (named_type, parse_error) {
    int colon = find_token_value(tokens, ":")    if colon >= 0 {
        name_tokens := slice_tokens(tokens, 0, colon)
        type_tokens := slice_tokens(tokens, colon + 1, len(tokens))
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
    vec[token] out = vec[token]()    int i = start    for i < end {
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
    int bracket = 0    int paren = 0    int i = 0    for i < len(tokens) {
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
    int bracket = 0    int paren = 0    int index = -1    int i = 0    for i < len(tokens) {
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
    int i = 0    for i < len(path) {
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
