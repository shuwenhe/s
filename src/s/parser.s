package s

use std.option.Option
use std.prelude.char_at
use std.prelude.len
use std.result.Result
use std.vec.Vec

struct ParseError {
    String message,
    i32 line,
    i32 column,
}

struct Parser {
    Vec[Token] tokens,
    i32 index,
}

func parse_source(String source) -> Result[SourceFile, ParseError] {
    match new_lexer(source).tokenize() {
        Result::Ok(tokens) => parse_tokens(tokens),
        Result::Err(err) => Result::Err(ParseError {
            message: err.message,
            line: err.line,
            column: err.column,
        }),
    }
}

func parse_tokens(Vec[Token] tokens) -> Result[SourceFile, ParseError] {
    var parser = Parser {
        tokens: tokens,
        index: 0,
    }
    parser.parse_source_file()
}

impl Parser {
    func parse_source_file(mut self) -> Result[SourceFile, ParseError] {
        self.expect_keyword("package")?
        var package = self.parse_path()?
        var uses = Vec[UseDecl]()
        var items = Vec[Item]()

        while self.at_keyword("use") {
            uses.push(self.parse_use_decl()?)
        }

        while !self.at(TokenKind::Eof) {
            items.push(self.parse_item()?)
        }

        Result::Ok(SourceFile {
            package: package,
            uses: uses,
            items: items,
        })
    }

    func parse_use_decl(mut self) -> Result[UseDecl, ParseError] {
        self.expect_keyword("use")?
        var path = self.parse_use_path()?
        var alias =
            if self.at_keyword("as") {
                self.advance()?
                Option::Some(self.expect_ident()?)
            } else {
                Option::None
            }
        Result::Ok(UseDecl {
            path: path,
            alias: alias,
        })
    }

    func parse_item(mut self) -> Result[Item, ParseError] {
        if self.at_keyword("func") {
            return Result::Ok(Item::Function(self.parse_function_decl()?))
        }
        if self.at_keyword("struct") {
            return Result::Ok(Item::Struct(self.parse_struct_decl()?))
        }
        if self.at_keyword("enum") {
            return Result::Ok(Item::Enum(self.parse_enum_decl()?))
        }
        if self.at_keyword("trait") {
            return Result::Ok(Item::Trait(self.parse_trait_decl()?))
        }
        if self.at_keyword("impl") {
            return Result::Ok(Item::Impl(self.parse_impl_decl()?))
        }
        Result::Err(self.error_here("unexpected token"))
    }

    func parse_function_decl(mut self) -> Result[FunctionDecl, ParseError] {
        var pair = self.parse_function(true)?
        Result::Ok(FunctionDecl {
            sig: pair.sig,
            body: pair.body,
            is_public: starts_with_upper(pair.sig.name),
        })
    }

    func parse_struct_decl(mut self) -> Result[StructDecl, ParseError] {
        self.expect_keyword("struct")?
        var name = self.expect_ident()?
        var generics = self.parse_generic_params()?
        self.expect_symbol("{")?
        var fields = Vec[Field]()

        while !self.eat_symbol("}") {
            var field = self.parse_named_type(Vec[String] { ",", "}" })?
            fields.push(Field {
                name: field.name,
                type_name: field.type_name,
                is_public: starts_with_upper(field.name),
            })
            self.eat_symbol(",")
        }

        Result::Ok(StructDecl {
            name: name,
            generics: generics,
            fields: fields,
            is_public: starts_with_upper(name),
        })
    }

    func parse_enum_decl(mut self) -> Result[EnumDecl, ParseError] {
        self.expect_keyword("enum")?
        var name = self.expect_ident()?
        var generics = self.parse_generic_params()?
        self.expect_symbol("{")?
        var variants = Vec[EnumVariant]()

        while !self.eat_symbol("}") {
            var variant_name = self.expect_ident()?
            var payload =
                if self.eat_symbol("(") {
                    var ty = self.parse_type_text(Vec[String] { ")" })?
                    self.expect_symbol(")")?
                    Option::Some(ty)
                } else {
                    Option::None
                }
            variants.push(EnumVariant {
                name: variant_name,
                payload: payload,
            })
            self.eat_symbol(",")
        }

        Result::Ok(EnumDecl {
            name: name,
            generics: generics,
            variants: variants,
            is_public: starts_with_upper(name),
        })
    }

    func parse_trait_decl(mut self) -> Result[TraitDecl, ParseError] {
        self.expect_keyword("trait")?
        var name = self.expect_ident()?
        var generics = self.parse_generic_params()?
        self.expect_symbol("{")?
        var methods = Vec[FunctionSig]()

        while !self.eat_symbol("}") {
            var pair = self.parse_function(false)?
            methods.push(pair.sig)
            self.expect_symbol(";")?
        }

        Result::Ok(TraitDecl {
            name: name,
            generics: generics,
            methods: methods,
            is_public: starts_with_upper(name),
        })
    }

    func parse_impl_decl(mut self) -> Result[ImplDecl, ParseError] {
        self.expect_keyword("impl")?
        var generics = self.parse_generic_params()?
        var first = self.parse_path()?
        var trait_name = Option::None
        var target = first

        if self.eat_keyword("for") {
            trait_name = Option::Some(first)
            target = self.parse_path()?
        }

        self.parse_where_clause()?
        self.expect_symbol("{")?
        var methods = Vec[FunctionDecl]()

        while !self.eat_symbol("}") {
            methods.push(self.parse_function_decl()?)
        }

        Result::Ok(ImplDecl {
            target: target,
            trait_name: trait_name,
            generics: generics,
            methods: methods,
        })
    }

    func parse_function(mut self, bool require_body) -> Result[ParsedFunction, ParseError] {
        self.expect_keyword("func")?
        var name = self.expect_ident()?
        var generics = self.parse_generic_params()?
        self.expect_symbol("(")?
        var params = self.parse_params()?
        self.expect_symbol(")")?

        var return_type =
            if self.eat_symbol("->") {
                Option::Some(self.parse_type_text(Vec[String] { "where", "{", ";" })?)
            } else {
                Option::None
            }

        self.parse_where_clause()?

        var body =
            if require_body {
                Option::Some(self.parse_block_expr()?)
            } else {
                Option::None
            }

        Result::Ok(ParsedFunction {
            sig: FunctionSig {
                name: name,
                generics: generics,
                params: params,
                return_type: return_type,
            },
            body: body,
        })
    }

    func parse_params(mut self) -> Result[Vec[Param], ParseError] {
        var params = Vec[Param]()
        if self.at_symbol(")") {
            return Result::Ok(params)
        }

        while true {
            var part = self.parse_named_type(Vec[String] { ",", ")" })?
            params.push(Param {
                name: part.name,
                type_name: part.type_name,
            })
            if !self.eat_symbol(",") || self.at_symbol(")") {
                break
            }
        }

        Result::Ok(params)
    }

    func parse_generic_params(mut self) -> Result[Vec[String], ParseError] {
        var generics = Vec[String]()
        if !self.eat_symbol("[") {
            return Result::Ok(generics)
        }

        while !self.eat_symbol("]") {
            var name = self.expect_ident()?
            var item =
                if self.eat_symbol(":") {
                    var bounds = Vec[String]()
                    bounds.push(self.parse_path()?)
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

        Result::Ok(generics)
    }

    func parse_where_clause(mut self) -> Result[(), ParseError] {
        if !self.eat_keyword("where") {
            return Result::Ok(())
        }
        while true {
            self.parse_type_text(Vec[String] { ",", "{", ";" })?
            if !self.eat_symbol(",") || self.at_symbol("{") || self.at_symbol(";") {
                break
            }
        }
        Result::Ok(())
    }

    func parse_named_type(mut self, Vec[String] stop_values) -> Result[NamedType, ParseError] {
        var segment = self.parse_token_segment(stop_values)?
        decode_named_type(segment)
    }

    func parse_token_segment(mut self, Vec[String] stop_values) -> Result[Vec[Token], ParseError] {
        var segment = Vec[Token]()
        var bracket = 0
        var paren = 0

        while true {
            var token = self.peek()?
            if token.kind == TokenKind::Eof {
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

        Result::Ok(segment)
    }

    func parse_block_expr(mut self) -> Result[BlockExpr, ParseError] {
        self.expect_symbol("{")?
        var statements = Vec[Stmt]()
        var final_expr = Option::None

        while !self.at_symbol("}") {
            if self.starts_stmt() {
                statements.push(self.parse_stmt()?)
                continue
            }
            var expr = self.parse_expr()?
            if self.eat_symbol(";") {
                statements.push(Stmt::Expr(ExprStmt { expr: expr }))
                continue
            }
            if !self.at_symbol("}") {
                statements.push(Stmt::Expr(ExprStmt { expr: expr }))
                continue
            }
            final_expr = Option::Some(expr)
            break
        }

        self.expect_symbol("}")?
        Result::Ok(BlockExpr {
            statements: statements,
            final_expr: final_expr,
            inferred_type: Option::None,
        })
    }

    func starts_stmt(self) -> bool {
        self.at_keyword("var")
            || self.at_keyword("return")
            || self.at_cfor_start()
            || self.looks_like_typed_var_stmt()
            || self.looks_like_increment_stmt()
            || self.looks_like_assignment_stmt()
    }

    func parse_stmt(mut self) -> Result[Stmt, ParseError] {
        if self.at_keyword("var") {
            return Result::Ok(Stmt::Var(self.parse_var_stmt(true)?))
        }
        if self.at_keyword("return") {
            return Result::Ok(Stmt::Return(self.parse_return_stmt()?))
        }
        if self.at_cfor_start() {
            return Result::Ok(Stmt::CFor(self.parse_cfor_stmt()?))
        }
        if self.looks_like_typed_var_stmt() {
            return Result::Ok(Stmt::Var(self.parse_typed_var_stmt(true)?))
        }
        if self.looks_like_increment_stmt() {
            return Result::Ok(Stmt::Increment(self.parse_increment_stmt(true)?))
        }
        if self.looks_like_assignment_stmt() {
            return Result::Ok(Stmt::Assign(self.parse_assign_stmt(true)?))
        }
        Result::Err(self.error_here("unexpected statement"))
    }

    func parse_var_stmt(mut self, bool consume_semicolon) -> Result[VarStmt, ParseError] {
        self.expect_keyword("var")?
        var name = self.expect_ident()?
        var type_name =
            if self.eat_symbol(":") {
                Option::Some(self.parse_type_text(Vec[String] { "=" })?)
            } else {
                Option::None
            }
        self.expect_symbol("=")?
        var value = self.parse_expr()?
        if consume_semicolon {
            self.eat_symbol(";")
        }
        Result::Ok(VarStmt {
            name: name,
            type_name: type_name,
            value: value,
        })
    }

    func parse_typed_var_stmt(mut self, bool consume_semicolon) -> Result[VarStmt, ParseError] {
        var segment = self.parse_token_segment(Vec[String] { "=" })?
        var named = decode_named_type(segment)?
        self.expect_symbol("=")?
        var value = self.parse_expr()?
        if consume_semicolon {
            self.eat_symbol(";")
        }
        Result::Ok(VarStmt {
            name: named.name,
            type_name: Option::Some(named.type_name),
            value: value,
        })
    }

    func parse_assign_stmt(mut self, bool consume_semicolon) -> Result[AssignStmt, ParseError] {
        var name = self.expect_ident()?
        self.expect_symbol("=")?
        var value = self.parse_expr()?
        if consume_semicolon {
            self.eat_symbol(";")
        }
        Result::Ok(AssignStmt {
            name: name,
            value: value,
        })
    }

    func parse_increment_stmt(mut self, bool consume_semicolon) -> Result[IncrementStmt, ParseError] {
        var name = self.expect_ident()?
        self.expect_symbol("++")?
        if consume_semicolon {
            self.eat_symbol(";")
        }
        Result::Ok(IncrementStmt {
            name: name,
        })
    }

    func parse_cfor_stmt(mut self) -> Result[CForStmt, ParseError] {
        self.expect_keyword("for")?
        self.expect_symbol("(")?
        var init = self.parse_for_clause_stmt()?
        self.expect_symbol(";")?
        var condition = self.parse_expr()?
        self.expect_symbol(";")?
        var step = self.parse_for_clause_stmt()?
        self.expect_symbol(")")?
        var body = self.parse_block_expr()?
        Result::Ok(CForStmt {
            init: box(init),
            condition: condition,
            step: box(step),
            body: body,
        })
    }

    func parse_for_clause_stmt(mut self) -> Result[Stmt, ParseError] {
        if self.at_keyword("var") {
            return Result::Ok(Stmt::Var(self.parse_var_stmt(false)?))
        }
        if self.looks_like_typed_var_stmt() {
            return Result::Ok(Stmt::Var(self.parse_typed_var_stmt(false)?))
        }
        if self.looks_like_increment_stmt() {
            return Result::Ok(Stmt::Increment(self.parse_increment_stmt(false)?))
        }
        if self.looks_like_assignment_stmt() {
            return Result::Ok(Stmt::Assign(self.parse_assign_stmt(false)?))
        }
        Result::Err(self.error_here("unexpected for clause"))
    }

    func parse_return_stmt(mut self) -> Result[ReturnStmt, ParseError] {
        self.expect_keyword("return")?
        if self.eat_symbol(";") {
            return Result::Ok(ReturnStmt {
                value: Option::None,
            })
        }
        var value = self.parse_expr()?
        self.eat_symbol(";")
        Result::Ok(ReturnStmt {
            value: Option::Some(value),
        })
    }

    func parse_expr(mut self) -> Result[Expr, ParseError] {
        if self.at_keyword("match") {
            return self.parse_match_expr()
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

    func parse_match_expr(mut self) -> Result[Expr, ParseError] {
        self.expect_keyword("match")?
        var subject = self.parse_expr()?
        self.expect_symbol("{")?
        var arms = Vec[MatchArm]()

        while !self.eat_symbol("}") {
            var pattern = self.parse_pattern()?
            self.expect_symbol("=>")?
            var expr = self.parse_expr()?
            arms.push(MatchArm {
                pattern: pattern,
                expr: expr,
            })
            self.eat_symbol(",")
        }

        Result::Ok(Expr::Match(MatchExpr {
            subject: Box(subject),
            arms: arms,
            inferred_type: Option::None,
        }))
    }

    func parse_if_expr(mut self) -> Result[Expr, ParseError] {
        self.expect_keyword("if")?
        var condition = self.parse_expr()?
        var then_branch = self.parse_block_expr()?
        var else_branch =
            if self.eat_keyword("else") {
                if self.at_keyword("if") {
                    Option::Some(Box(self.parse_if_expr()?))
                } else {
                    Option::Some(Box(Expr::Block(self.parse_block_expr()?)))
                }
            } else {
                Option::None
            }

        Result::Ok(Expr::If(IfExpr {
            condition: Box(condition),
            then_branch: then_branch,
            else_branch: else_branch,
            inferred_type: Option::None,
        }))
    }

    func parse_while_expr(mut self) -> Result[Expr, ParseError] {
        self.expect_keyword("while")?
        var condition = self.parse_expr()?
        var body = self.parse_block_expr()?
        Result::Ok(Expr::While(WhileExpr {
            condition: Box(condition),
            body: body,
            inferred_type: Option::None,
        }))
    }

    func parse_for_expr(mut self) -> Result[Expr, ParseError] {
        self.expect_keyword("for")?
        var name = self.expect_ident()?
        self.expect_keyword("in")?
        var iterable = self.parse_expr()?
        var body = self.parse_block_expr()?
        Result::Ok(Expr::For(ForExpr {
            name: name,
            iterable: Box(iterable),
            body: body,
            inferred_type: Option::None,
        }))
    }

    func parse_pattern(mut self) -> Result[Pattern, ParseError] {
        if self.eat_ident_value("_") {
            return Result::Ok(Pattern::Wildcard(WildcardPattern {}))
        }

        var path = self.parse_path()?
        if self.eat_symbol("(") {
            var args = Vec[Pattern]()
            if !self.at_symbol(")") {
                while true {
                    args.push(self.parse_pattern()?)
                    if !self.eat_symbol(",") || self.at_symbol(")") {
                        break
                    }
                }
            }
            self.expect_symbol(")")?
            return Result::Ok(Pattern::Variant(VariantPattern {
                path: path,
                args: args,
            }))
        }

        if path_contains_dot(path) || starts_with_upper(path) {
            return Result::Ok(Pattern::Variant(VariantPattern {
                path: path,
                args: Vec[Pattern](),
            }))
        }

        Result::Ok(Pattern::Name(NamePattern { name: path }))
    }

    func parse_binary_expr(mut self, i32 min_precedence) -> Result[Expr, ParseError] {
        var expr = self.parse_unary_expr()?
        while true {
            var token = self.peek()?
            var precedence = self.binary_precedence(token.value)
            if precedence < min_precedence {
                break
            }
            var op = self.advance()?.value
            var rhs = self.parse_binary_expr(precedence + 1)?
            expr = Expr::Binary(BinaryExpr {
                left: Box(expr),
                op: op,
                right: Box(rhs),
                inferred_type: Option::None,
            })
        }
        Result::Ok(expr)
    }

    func parse_unary_expr(mut self) -> Result[Expr, ParseError] {
        if self.eat_symbol("&") {
            var mutable = self.eat_keyword("mut")
            var target = self.parse_unary_expr()?
            return Result::Ok(Expr::Borrow(BorrowExpr {
                target: Box(target),
                mutable: mutable,
                inferred_type: Option::None,
            }))
        }
        self.parse_call_expr()
    }

    func parse_call_expr(mut self) -> Result[Expr, ParseError] {
        var expr = self.parse_primary_expr()?
        while true {
            if self.eat_symbol("(") {
                var args = Vec[Expr]()
                if !self.at_symbol(")") {
                    while true {
                        args.push(self.parse_expr()?)
                        if !self.eat_symbol(",") || self.at_symbol(")") {
                            break
                        }
                    }
                }
                self.expect_symbol(")")?
                expr = Expr::Call(CallExpr {
                    callee: Box(expr),
                    args: args,
                    inferred_type: Option::None,
                })
                continue
            }
            if self.eat_symbol(".") {
                expr = Expr::Member(MemberExpr {
                    target: Box(expr),
                    member: self.expect_ident()?,
                    inferred_type: Option::None,
                })
                continue
            }
            if self.eat_symbol("[") {
                var index = self.parse_expr()?
                self.expect_symbol("]")?
                expr = Expr::Index(IndexExpr {
                    target: Box(expr),
                    index: Box(index),
                    inferred_type: Option::None,
                })
                continue
            }
            break
        }
        Result::Ok(expr)
    }

    func parse_primary_expr(mut self) -> Result[Expr, ParseError] {
        var token = self.peek()?
        if token.kind == TokenKind::Int {
            self.advance()?
            return Result::Ok(Expr::Int(IntExpr {
                value: token.value,
                inferred_type: Option::None,
            }))
        }
        if token.kind == TokenKind::String {
            self.advance()?
            return Result::Ok(Expr::String(StringExpr {
                value: token.value,
                inferred_type: Option::None,
            }))
        }
        if self.at_keyword("true") {
            self.advance()?
            return Result::Ok(Expr::Bool(BoolExpr {
                value: true,
                inferred_type: Option::None,
            }))
        }
        if self.at_keyword("false") {
            self.advance()?
            return Result::Ok(Expr::Bool(BoolExpr {
                value: false,
                inferred_type: Option::None,
            }))
        }
        if self.at_symbol("{") {
            return Result::Ok(Expr::Block(self.parse_block_expr()?))
        }
        if self.eat_symbol("(") {
            var expr = self.parse_expr()?
            self.expect_symbol(")")?
            return Result::Ok(expr)
        }
        Result::Ok(Expr::Name(NameExpr {
            name: self.expect_ident()?,
            inferred_type: Option::None,
        }))
    }

    func binary_precedence(self, String op) -> i32 {
        match op {
            "||" => 1,
            "&&" => 2,
            "==" => 3,
            "!=" => 3,
            "<" => 4,
            "<=" => 4,
            ">" => 4,
            ">=" => 4,
            "+" => 5,
            "-" => 5,
            "*" => 6,
            "/" => 6,
            "%" => 6,
            _ => -1,
        }
    }

    func parse_use_path(mut self) -> Result[String, ParseError] {
        var parts = Vec[String]()
        parts.push(self.expect_ident()?)
        while self.eat_symbol(".") {
            if self.eat_symbol("{") {
                var members = Vec[String]()
                while !self.eat_symbol("}") {
                    var member = self.expect_ident()?
                    var text =
                        if self.eat_keyword("as") {
                            member + " as " + self.expect_ident()?
                        } else {
                            member
                        }
                    members.push(text)
                    self.eat_symbol(",")
                }
                return Result::Ok(join_strings(parts, ".") + ".{" + join_strings(members, ", ") + "}")
            }
            parts.push(self.expect_ident()?)
        }
        Result::Ok(join_strings(parts, "."))
    }

    func parse_path(mut self) -> Result[String, ParseError] {
        var parts = Vec[String]()
        parts.push(self.expect_ident()?)
        while self.eat_symbol(".") {
            parts.push(self.expect_ident()?)
        }
        if self.at_symbol("[") {
            var last = parts.pop().unwrap()
            parts.push(last + self.parse_bracket_group()?)
        }
        Result::Ok(join_strings(parts, "."))
    }

    func parse_type_text(mut self, Vec[String] stop_values) -> Result[String, ParseError] {
        var parts = Vec[String]()
        var bracket = 0
        var paren = 0

        while true {
            var token = self.peek()?
            if token.kind == TokenKind::Eof {
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

        Result::Ok(normalize_type_text(join_strings(parts, " ")))
    }

    func parse_bracket_group(mut self) -> Result[String, ParseError] {
        var parts = Vec[String]()
        parts.push(self.advance()?.value)
        var depth = 1
        while depth > 0 {
            var token = self.advance()?
            parts.push(token.value)
            if token.value == "[" {
                depth = depth + 1
            } else if token.value == "]" {
                depth = depth - 1
            }
        }
        Result::Ok(
            join_strings(parts, " ")
                .replace("[ ", "[")
                .replace(" ]", "]")
                .replace(" ,", ",")
        )
    }

    func at(self, TokenKind kind) -> bool {
        self.peek().unwrap().kind == kind
    }

    func at_keyword(self, String value) -> bool {
        var token = self.peek().unwrap()
        token.kind == TokenKind::Keyword && token.value == value
    }

    func at_symbol(self, String value) -> bool {
        var token = self.peek().unwrap()
        token.kind == TokenKind::Symbol && token.value == value
    }

    func at_cfor_start(self) -> bool {
        self.at_keyword("for") && self.peek_at(1).unwrap().kind == TokenKind::Symbol && self.peek_at(1).unwrap().value == "("
    }

    func looks_like_assignment_stmt(self) -> bool {
        var first = self.peek().unwrap()
        var second = self.peek_at(1).unwrap()
        first.kind == TokenKind::Ident && second.kind == TokenKind::Symbol && second.value == "="
    }

    func looks_like_increment_stmt(self) -> bool {
        var first = self.peek().unwrap()
        var second = self.peek_at(1).unwrap()
        first.kind == TokenKind::Ident && second.kind == TokenKind::Symbol && second.value == "++"
    }

    func looks_like_typed_var_stmt(self) -> bool {
        var offset = self.find_top_level_symbol_offset("=")
        if offset <= 0 {
            return false
        }
        decode_named_type(slice_tokens(self.tokens, self.index, self.index + offset)).is_ok()
    }

    func eat_keyword(mut self, String value) -> bool {
        if self.at_keyword(value) {
            self.advance().unwrap()
            return true
        }
        false
    }

    func eat_ident_value(mut self, String value) -> bool {
        var token = self.peek().unwrap()
        if token.kind == TokenKind::Ident && token.value == value {
            self.advance().unwrap()
            return true
        }
        false
    }

    func eat_symbol(mut self, String value) -> bool {
        if self.at_symbol(value) {
            self.advance().unwrap()
            return true
        }
        false
    }

    func expect_keyword(mut self, String value) -> Result[Token, ParseError] {
        var token = self.peek()?
        if token.kind == TokenKind::Keyword && token.value == value {
            return self.advance()
        }
        Result::Err(ParseError {
            message: "expected keyword " + value,
            line: token.line,
            column: token.column,
        })
    }

    func expect_symbol(mut self, String value) -> Result[Token, ParseError] {
        var token = self.peek()?
        if token.kind == TokenKind::Symbol && token.value == value {
            return self.advance()
        }
        Result::Err(ParseError {
            message: "expected symbol " + value,
            line: token.line,
            column: token.column,
        })
    }

    func expect_ident(mut self) -> Result[String, ParseError] {
        var token = self.peek()?
        if token.kind == TokenKind::Ident {
            self.advance()?
            return Result::Ok(token.value)
        }
        if token.kind == TokenKind::Keyword && token.value == "self" {
            self.advance()?
            return Result::Ok(token.value)
        }
        Result::Err(ParseError {
            message: "expected identifier",
            line: token.line,
            column: token.column,
        })
    }

    func peek(self) -> Result[Token, ParseError] {
        self.peek_at(0)
    }

    func peek_at(self, i32 offset) -> Result[Token, ParseError] {
        if self.index >= len(self.tokens) {
            return Result::Err(ParseError {
                message: "unexpected eof",
                line: 0,
                column: 0,
            })
        }
        var target = self.index + offset
        if target >= len(self.tokens) {
            target = len(self.tokens) - 1
        }
        Result::Ok(self.tokens[target])
    }

    func advance(mut self) -> Result[Token, ParseError] {
        var token = self.peek()?
        self.index = self.index + 1
        Result::Ok(token)
    }

    func error_here(self, String message) -> ParseError {
        var token = self.peek().unwrap()
        ParseError {
            message: message,
            line: token.line,
            column: token.column,
        }
    }
}

impl Parser {
    func find_top_level_symbol_offset(self, String value) -> i32 {
        var bracket = 0
        var paren = 0
        var offset = 0
        while self.index + offset < len(self.tokens) {
            var token = self.tokens[self.index + offset]
            if token.kind == TokenKind::Eof {
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

struct ParsedFunction {
    FunctionSig sig,
    Option[BlockExpr] body,
}

struct NamedType {
    String name,
    String type_name,
}

func decode_named_type(Vec[Token] tokens) -> Result[NamedType, ParseError] {
    var colon = find_token_value(tokens, ":")
    if colon >= 0 {
        var name_tokens = slice_tokens(tokens, 0, colon)
        var type_tokens = slice_tokens(tokens, colon + 1, len(tokens))
        return Result::Ok(NamedType {
            name: normalize_type_text(join_token_values(name_tokens)),
            type_name: normalize_type_text(join_token_values(type_tokens)),
        })
    }

    var split = find_decl_name_index(tokens)
    if split <= 0 {
        return Result::Err(ParseError {
            message: "expected typed name",
            line: 0,
            column: 0,
        })
    }
    Result::Ok(NamedType {
        name: tokens[split].value,
        type_name: normalize_type_text(join_token_values(slice_tokens(tokens, 0, split))),
    })
}

func slice_tokens(Vec[Token] tokens, i32 start, i32 end) -> Vec[Token] {
    var out = Vec[Token]()
    var i = start
    while i < end {
        out.push(tokens[i])
        i = i + 1
    }
    out
}

func join_token_values(Vec[Token] tokens) -> String {
    var parts = Vec[String]()
    for token in tokens {
        parts.push(token.value)
    }
    join_strings(parts, " ")
}

func find_token_value(Vec[Token] tokens, String value) -> i32 {
    var bracket = 0
    var paren = 0
    var i = 0
    while i < len(tokens) {
        var token = tokens[i]
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

func find_decl_name_index(Vec[Token] tokens) -> i32 {
    var bracket = 0
    var paren = 0
    var index = -1
    var i = 0
    while i < len(tokens) {
        var token = tokens[i]
        if token.value == "[" {
            bracket = bracket + 1
        } else if token.value == "]" {
            bracket = bracket - 1
        } else if token.value == "(" {
            paren = paren + 1
        } else if token.value == ")" {
            paren = paren - 1
        } else if bracket == 0 && paren == 0 && token.kind == TokenKind::Ident {
            index = i
        }
        i = i + 1
    }
    index
}

func normalize_type_text(String text) -> String {
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

func contains_string(Vec[String] values, String target) -> bool {
    for value in values {
        if value == target {
            return true
        }
    }
    false
}

func join_strings(Vec[String] values, String sep) -> String {
    var out = ""
    var first = true
    for value in values {
        if !first {
            out = out + sep
        }
        out = out + value
        first = false
    }
    out
}

func path_contains_dot(String path) -> bool {
    var i = 0
    while i < len(path) {
        if char_at(path, i) == "." {
            return true
        }
        i = i + 1
    }
    false
}

func starts_with_upper(String text) -> bool {
    if text == "" {
        return false
    }
    var ch = char_at(text, 0)
    match ch {
        "A" => true,
        "B" => true,
        "C" => true,
        "D" => true,
        "E" => true,
        "F" => true,
        "G" => true,
        "H" => true,
        "I" => true,
        "J" => true,
        "K" => true,
        "L" => true,
        "M" => true,
        "N" => true,
        "O" => true,
        "P" => true,
        "Q" => true,
        "R" => true,
        "S" => true,
        "T" => true,
        "U" => true,
        "V" => true,
        "W" => true,
        "X" => true,
        "Y" => true,
        "Z" => true,
        _ => false,
    }
}
