package frontend

use std.option.Option
use std.prelude.char_at
use std.prelude.len
use std.result.Result
use std.vec.Vec

pub struct ParseError {
    message: String,
    line: i32,
    column: i32,
}

pub struct Parser {
    tokens: Vec[Token],
    index: i32,
}

fn parse_source(source: String) -> Result[SourceFile, ParseError] {
    match new_lexer(source).tokenize() {
        Result::Ok(tokens) => parse_tokens(tokens),
        Result::Err(err) => Result::Err(ParseError {
            message: err.message,
            line: err.line,
            column: err.column,
        }),
    }
}

fn parse_tokens(tokens: Vec[Token]) -> Result[SourceFile, ParseError] {
    var parser = Parser {
        tokens: tokens,
        index: 0,
    }
    parser.parse_source_file()
}

impl Parser {
    fn parse_source_file(mut self) -> Result[SourceFile, ParseError] {
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

    fn parse_use_decl(mut self) -> Result[UseDecl, ParseError] {
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

    fn parse_item(mut self) -> Result[Item, ParseError] {
        if self.at_keyword("fn") {
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

    fn parse_function_decl(mut self) -> Result[FunctionDecl, ParseError] {
        var pair = self.parse_function(true)?
        Result::Ok(FunctionDecl {
            sig: pair.sig,
            body: pair.body,
            is_public: starts_with_upper(pair.sig.name),
        })
    }

    fn parse_struct_decl(mut self) -> Result[StructDecl, ParseError] {
        self.expect_keyword("struct")?
        var name = self.expect_ident()?
        var generics = self.parse_generic_params()?
        self.expect_symbol("{")?
        var fields = Vec[Field]()

        while !self.eat_symbol("}") {
            var field_name = self.expect_ident()?
            self.expect_symbol(":")?
            var field_type = self.parse_type_text(Vec[String] { ",", "}" })?
            fields.push(Field {
                name: field_name,
                type_name: field_type,
                is_public: starts_with_upper(field_name),
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

    fn parse_enum_decl(mut self) -> Result[EnumDecl, ParseError] {
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

    fn parse_trait_decl(mut self) -> Result[TraitDecl, ParseError] {
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

    fn parse_impl_decl(mut self) -> Result[ImplDecl, ParseError] {
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

    fn parse_function(mut self, require_body: bool) -> Result[ParsedFunction, ParseError] {
        self.expect_keyword("fn")?
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

    fn parse_params(mut self) -> Result[Vec[Param], ParseError] {
        var params = Vec[Param]()
        if self.at_symbol(")") {
            return Result::Ok(params)
        }

        while true {
            var name = self.parse_param_name()?
            self.expect_symbol(":")?
            var type_name = self.parse_type_text(Vec[String] { ",", ")" })?
            params.push(Param {
                name: name,
                type_name: type_name,
            })
            if !self.eat_symbol(",") || self.at_symbol(")") {
                break
            }
        }

        Result::Ok(params)
    }

    fn parse_param_name(mut self) -> Result[String, ParseError] {
        if self.eat_keyword("mut") {
            return Result::Ok("mut " + self.expect_ident()?)
        }
        if self.eat_symbol("&") {
            var prefix =
                if self.eat_keyword("mut") {
                    "&mut "
                } else {
                    "&"
                }
            if self.eat_keyword("self") {
                return Result::Ok(prefix + "self")
            }
            return Result::Ok(prefix + self.expect_ident()?)
        }
        if self.eat_keyword("self") {
            return Result::Ok("self")
        }
        self.expect_ident()
    }

    fn parse_generic_params(mut self) -> Result[Vec[String], ParseError] {
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

    fn parse_where_clause(mut self) -> Result[(), ParseError] {
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

    fn parse_block_expr(mut self) -> Result[BlockExpr, ParseError] {
        self.expect_symbol("{")?
        var statements = Vec[Stmt]()
        var final_expr = Option::None

        while !self.at_symbol("}") {
            if self.at_keyword("var") {
                statements.push(Stmt::Var(self.parse_var_stmt()?))
                continue
            }
            if self.at_keyword("return") {
                statements.push(Stmt::Return(self.parse_return_stmt()?))
                continue
            }

            var expr = self.parse_expr()?
            if self.eat_symbol(";") {
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

    fn parse_var_stmt(mut self) -> Result[VarStmt, ParseError] {
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
        self.eat_symbol(";")
        Result::Ok(VarStmt {
            name: name,
            type_name: type_name,
            value: value,
        })
    }

    fn parse_return_stmt(mut self) -> Result[ReturnStmt, ParseError] {
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

    fn parse_expr(mut self) -> Result[Expr, ParseError] {
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

    fn parse_match_expr(mut self) -> Result[Expr, ParseError] {
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

    fn parse_if_expr(mut self) -> Result[Expr, ParseError] {
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

    fn parse_while_expr(mut self) -> Result[Expr, ParseError] {
        self.expect_keyword("while")?
        var condition = self.parse_expr()?
        var body = self.parse_block_expr()?
        Result::Ok(Expr::While(WhileExpr {
            condition: Box(condition),
            body: body,
            inferred_type: Option::None,
        }))
    }

    fn parse_for_expr(mut self) -> Result[Expr, ParseError] {
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

    fn parse_pattern(mut self) -> Result[Pattern, ParseError] {
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

    fn parse_binary_expr(mut self, min_precedence: i32) -> Result[Expr, ParseError] {
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

    fn parse_unary_expr(mut self) -> Result[Expr, ParseError] {
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

    fn parse_call_expr(mut self) -> Result[Expr, ParseError] {
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

    fn parse_primary_expr(mut self) -> Result[Expr, ParseError] {
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

    fn binary_precedence(self, op: String) -> i32 {
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

    fn parse_use_path(mut self) -> Result[String, ParseError] {
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

    fn parse_path(mut self) -> Result[String, ParseError] {
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

    fn parse_type_text(mut self, stop_values: Vec[String]) -> Result[String, ParseError] {
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

    fn parse_bracket_group(mut self) -> Result[String, ParseError] {
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

    fn at(self, kind: TokenKind) -> bool {
        self.peek().unwrap().kind == kind
    }

    fn at_keyword(self, value: String) -> bool {
        var token = self.peek().unwrap()
        token.kind == TokenKind::Keyword && token.value == value
    }

    fn at_symbol(self, value: String) -> bool {
        var token = self.peek().unwrap()
        token.kind == TokenKind::Symbol && token.value == value
    }

    fn eat_keyword(mut self, value: String) -> bool {
        if self.at_keyword(value) {
            self.advance().unwrap()
            return true
        }
        false
    }

    fn eat_ident_value(mut self, value: String) -> bool {
        var token = self.peek().unwrap()
        if token.kind == TokenKind::Ident && token.value == value {
            self.advance().unwrap()
            return true
        }
        false
    }

    fn eat_symbol(mut self, value: String) -> bool {
        if self.at_symbol(value) {
            self.advance().unwrap()
            return true
        }
        false
    }

    fn expect_keyword(mut self, value: String) -> Result[Token, ParseError] {
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

    fn expect_symbol(mut self, value: String) -> Result[Token, ParseError] {
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

    fn expect_ident(mut self) -> Result[String, ParseError] {
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

    fn peek(self) -> Result[Token, ParseError] {
        if self.index >= len(self.tokens) {
            return Result::Err(ParseError {
                message: "unexpected eof",
                line: 0,
                column: 0,
            })
        }
        Result::Ok(self.tokens[self.index])
    }

    fn advance(mut self) -> Result[Token, ParseError] {
        var token = self.peek()?
        self.index = self.index + 1
        Result::Ok(token)
    }

    fn error_here(self, message: String) -> ParseError {
        var token = self.peek().unwrap()
        ParseError {
            message: message,
            line: token.line,
            column: token.column,
        }
    }
}

pub struct ParsedFunction {
    sig: FunctionSig,
    body: Option[BlockExpr],
}

fn normalize_type_text(text: String) -> String {
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

fn contains_string(values: Vec[String], target: String) -> bool {
    for value in values {
        if value == target {
            return true
        }
    }
    false
}

fn join_strings(values: Vec[String], sep: String) -> String {
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

fn path_contains_dot(path: String) -> bool {
    var i = 0
    while i < len(path) {
        if char_at(path, i) == "." {
            return true
        }
        i = i + 1
    }
    false
}

fn starts_with_upper(text: String) -> bool {
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
