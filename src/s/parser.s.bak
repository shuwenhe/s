package s

use std.option.Option
use std.prelude.charAt
use std.prelude.len
use std.result.Result
use std.vec.Vec

struct ParseError {
    string message,
    int32 line,
    int32 column,
}

struct Parser {
    Vec[Token] tokens,
    int32 index,
}

func parseSource(string source) Result[SourceFile, ParseError] {
    match newLexer(source).tokenize() {
        Result::Ok(tokens) => parseTokens(tokens),
        Result::Err(err) => Result::Err(ParseError {
            message: err.message,
            line: err.line,
            column: err.column,
        }),
    }
}

func parseTokens(Vec[Token] tokens) Result[SourceFile, ParseError] {
    var parser = Parser {
        tokens: tokens,
        index: 0,
    }
    parser.parseSourceFile()
}

impl Parser {
    func parseSourceFile(mut self) Result[SourceFile, ParseError] {
        self.expectKeyword("package")?
        var package = self.parsePath()?
        var uses = Vec[UseDecl]()
        var items = Vec[Item]()

        while self.atKeyword("use") {
            uses.push(self.parseUseDecl()?)
        }

        while !self.at(TokenKind::Eof) {
            items.push(self.parseItem()?)
        }

        Result::Ok(SourceFile {
            pkg: package,
            uses: uses,
            items: items,
        })
    }

    func parseUseDecl(mut self) Result[UseDecl, ParseError] {
        self.expectKeyword("use")?
        var path = self.parseUsePath()?
        var alias =
            if self.atKeyword("as") {
                self.advance()?
                Option::Some(self.expectIdent()?)
            } else {
                Option::None
            }
        Result::Ok(UseDecl {
            path: path,
            alias: alias,
        })
    }

    func parseItem(mut self) Result[Item, ParseError] {
        if self.atKeyword("func") {
            // parse a function; if it has a receiver, convert to an impl item
            var parsed = self.parseFunction(true)?
            match parsed.receiver {
                Option::Some(r) => {
                    // build FunctionDecl for method
                    var method = FunctionDecl {
                        sig: parsed.sig,
                        body: parsed.body,
                        isPublic: startsWithUpper(parsed.sig.name),
                    }
                    var impl = ImplDecl {
                        target: r.typeName,
                        traitName: Option::None,
                        generics: Vec[string](),
                        methods: Vec[FunctionDecl] { method },
                    }
                    return Result::Ok(Item::Impl(impl))
                }
                Option::None => return Result::Ok(Item::Function(self.parseFunctionDecl()?)),
            }
        }
        if self.atKeyword("struct") {
            return Result::Ok(Item::Struct(self.parseStructDecl()?))
        }
        if self.atKeyword("enum") {
            return Result::Ok(Item::Enum(self.parseEnumDecl()?))
        }
        if self.atKeyword("trait") {
            return Result::Ok(Item::Trait(self.parseTraitDecl()?))
        }
        if self.atKeyword("impl") {
            return Result::Ok(Item::Impl(self.parseImplDecl()?))
        }
        Result::Err(self.errorHere("unexpected token"))
    }

    func parseFunctionDecl(mut self) Result[FunctionDecl, ParseError] {
        var pair = self.parseFunction(true)?
        if pair.receiver.isSome() {
            return Result::Err(self.errorHere("method receiver not allowed in this context"))
        }
        Result::Ok(FunctionDecl {
            sig: pair.sig,
            body: pair.body,
            isPublic: startsWithUpper(pair.sig.name),
        })
    }

    func parseStructDecl(mut self) Result[StructDecl, ParseError] {
        self.expectKeyword("struct")?
        var name = self.expectIdent()?
        var generics = self.parseGenericParams()?
        self.expectSymbol("{")?
        var fields = Vec[Field]()

        while !self.eatSymbol("}") {
            var field = self.parseNamedType(Vec[string] { ",", "}" })?
            fields.push(Field {
                name: field.name,
                typeName: field.typeName,
                isPublic: startsWithUpper(field.name),
            })
            self.eatSymbol(",")
        }

        Result::Ok(StructDecl {
            name: name,
            generics: generics,
            fields: fields,
            isPublic: startsWithUpper(name),
        })
    }

    func parseEnumDecl(mut self) Result[EnumDecl, ParseError] {
        self.expectKeyword("enum")?
        var name = self.expectIdent()?
        var generics = self.parseGenericParams()?
        self.expectSymbol("{")?
        var variants = Vec[EnumVariant]()

        while !self.eatSymbol("}") {
            var variantName = self.expectIdent()?
            var payload =
                if self.eatSymbol("(") {
                    var ty = self.parseTypeText(Vec[string] { ")" })?
                    self.expectSymbol(")")?
                    Option::Some(ty)
                } else {
                    Option::None
                }
            variants.push(EnumVariant {
                name: variantName,
                payload: payload,
            })
            self.eatSymbol(",")
        }

        Result::Ok(EnumDecl {
            name: name,
            generics: generics,
            variants: variants,
            isPublic: startsWithUpper(name),
        })
    }

    func parseTraitDecl(mut self) Result[TraitDecl, ParseError] {
        self.expectKeyword("trait")?
        var name = self.expectIdent()?
        var generics = self.parseGenericParams()?
        self.expectSymbol("{")?
        var methods = Vec[FunctionSig]()

        while !self.eatSymbol("}") {
            var pair = self.parseFunction(false)?
            methods.push(pair.sig)
            self.expectSymbol(";")?
        }

        Result::Ok(TraitDecl {
            name: name,
            generics: generics,
            methods: methods,
            isPublic: startsWithUpper(name),
        })
    }

    func parseImplDecl(mut self) Result[ImplDecl, ParseError] {
        self.expectKeyword("impl")?
        var generics = self.parseGenericParams()?
        var first = self.parsePath()?
        var traitName = Option::None
        var target = first

        if self.eatKeyword("for") {
            traitName = Option::Some(first)
            target = self.parsePath()?
        }

        self.parseWhereClause()?
        self.expectSymbol("{")?
        var methods = Vec[FunctionDecl]()

        while !self.eatSymbol("}") {
            methods.push(self.parseFunctionDecl()?)
        }

        Result::Ok(ImplDecl {
            target: target,
            traitName: traitName,
            generics: generics,
            methods: methods,
        })
    }

    func parseFunction(mut self, bool requireBody) Result[ParsedFunction, ParseError] {
        self.expectKeyword("func")?
        // optional receiver syntax: (name type)
        var receiver = Option::None
        if self.atSymbol("(") {
            self.expectSymbol("(")?
            var named = self.parseNamedType(Vec[string] { ")" })?
            self.expectSymbol(")")?
            receiver = Option::Some(named)
        }
        var name = self.expectIdent()?
        var generics = self.parseGenericParams()?
        self.expectSymbol("(")?
        var params = self.parseParams()?
        self.expectSymbol(")")?

        // Parse return type in Go-style: return type is written after
        // the parameter list (no arrow). We accept absence of return
        // type if the next token is a where-clause, block start, or
        // semicolon. This keeps compatibility with trait/method
        // declarations that may omit a body.
        var returnType = Option::None
        var next = self.peek()?
        if !(next.kind == TokenKind::Symbol && (next.value == "{" || next.value == ";")) && !(
            next.kind == TokenKind::Keyword && next.value == "where"
        ) {
            // treat following token sequence as a type until where/{/;
            returnType = Option::Some(self.parseTypeText(Vec[string] { "where", "{", ";" })?)
        }

        self.parseWhereClause()?

        var body =
            if requireBody {
                Option::Some(self.parseBlockExpr()?)
            } else {
                Option::None
            }

        Result::Ok(ParsedFunction {
            sig: FunctionSig {
                name: name,
                generics: generics,
                params: params,
                returnType: returnType,
            },
            body: body,
            receiver: receiver,
        })
    }

    func parseParams(mut self) Result[Vec[Param], ParseError] {
        var params = Vec[Param]()
        if self.atSymbol(")") {
            return Result::Ok(params)
        }

        while true {
            var part = self.parseNamedType(Vec[string] { ",", ")" })?
            params.push(Param {
                name: part.name,
                typeName: part.typeName,
            })
            if !self.eatSymbol(",") || self.atSymbol(")") {
                break
            }
        }

        Result::Ok(params)
    }

    func parseGenericParams(mut self) Result[Vec[string], ParseError] {
        var generics = Vec[string]()
        if !self.eatSymbol("[") {
            return Result::Ok(generics)
        }

        while !self.eatSymbol("]") {
            var name = self.expectIdent()?
            var item =
                if self.eatSymbol(":") {
                    var bounds = Vec[string]()
                    bounds.push(self.parsePath()?)
                    while self.eatSymbol("+") {
                        bounds.push(self.parsePath()?)
                    }
                    name + ": " + joinStrings(bounds, " + ")
                } else {
                    name
                }
            generics.push(item)
            self.eatSymbol(",")
        }

        Result::Ok(generics)
    }

    func parseWhereClause(mut self) Result[(), ParseError] {
        if !self.eatKeyword("where") {
            return Result::Ok(())
        }
        while true {
            self.parseTypeText(Vec[string] { ",", "{", ";" })?
            if !self.eatSymbol(",") || self.atSymbol("{") || self.atSymbol(";") {
                break
            }
        }
        Result::Ok(())
    }

    func parseNamedType(mut self, Vec[string] stopValues) Result[NamedType, ParseError] {
        var segment = self.parseTokenSegment(stopValues)?
        decodeNamedType(segment)
    }

    func parseTokenSegment(mut self, Vec[string] stopValues) Result[Vec[Token], ParseError] {
        var segment = Vec[Token]()
        var bracket = 0
        var paren = 0

        while true {
            var token = self.peek()?
            if token.kind == TokenKind::Eof {
                break
            }
            if bracket == 0 && paren == 0 && containsString(stopValues, token.value) {
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

    func parseBlockExpr(mut self) Result[BlockExpr, ParseError] {
        self.expectSymbol("{")?
        var statements = Vec[Stmt]()
        var finalExpr = Option::None

        while !self.atSymbol("}") {
            if self.startsStmt() {
                statements.push(self.parseStmt()?)
                continue
            }
            var expr = self.parseExpr()?
            if self.eatSymbol(";") {
                statements.push(Stmt::Expr(ExprStmt { expr: expr }))
                continue
            }
            if !self.atSymbol("}") {
                statements.push(Stmt::Expr(ExprStmt { expr: expr }))
                continue
            }
            finalExpr = Option::Some(expr)
            break
        }

        self.expectSymbol("}")?
        Result::Ok(BlockExpr {
            statements: statements,
            finalExpr: finalExpr,
            inferredType: Option::None,
        })
    }

    func startsStmt(self) bool {
        self.atKeyword("var")
            || self.atKeyword("return")
            || self.atKeyword("defer")
            || self.atCforStart()
            || self.looksLikeTypedVarStmt()
            || self.looksLikeIncrementStmt()
            || self.looksLikeAssignmentStmt()
            || self.looksLikeShortVarStmt()
    }

    func parseStmt(mut self) Result[Stmt, ParseError] {
        if self.atKeyword("var") {
            return Result::Ok(Stmt::Var(self.parseVarStmt(true)?))
        }
        if self.atKeyword("defer") {
            return Result::Ok(Stmt::Defer(self.parseDeferStmt()?))
        }
        if self.atKeyword("return") {
            return Result::Ok(Stmt::Return(self.parseReturnStmt()?))
        }
        if self.atCforStart() {
            return Result::Ok(Stmt::CFor(self.parseCforStmt()?))
        }
        if self.looksLikeTypedVarStmt() {
            return Result::Ok(Stmt::Var(self.parseTypedVarStmt(true)?))
        }
        if self.looksLikeIncrementStmt() {
            return Result::Ok(Stmt::Increment(self.parseIncrementStmt(true)?))
        }
        if self.looksLikeAssignmentStmt() {
            return Result::Ok(Stmt::Assign(self.parseAssignStmt(true)?))
        }
        if self.looksLikeShortVarStmt() {
            return Result::Ok(Stmt::Var(self.parseShortVarStmt(true)?))
        }
        Result::Err(self.errorHere("unexpected statement"))
    }

    func parseVarStmt(mut self, bool consumeSemicolon) Result[VarStmt, ParseError] {
        self.expectKeyword("var")?
        var name = self.expectIdent()?
        var typeName =
            if self.eatSymbol(":") {
                Option::Some(self.parseTypeText(Vec[string] { "=" })?)
            } else {
                Option::None
            }
        self.expectSymbol("=")?
        var value = self.parseExpr()?
        if consumeSemicolon {
            self.eatSymbol(";")
        }
        Result::Ok(VarStmt {
            name: name,
            typeName: typeName,
            value: value,
        })
    }

    func parseShortVarStmt(mut self, bool consumeSemicolon) Result[VarStmt, ParseError] {
        var name = self.expectIdent()?
        self.expectSymbol(":=")?
        var value = self.parseExpr()?
        if consumeSemicolon {
            self.eatSymbol(";")
        }
        Result::Ok(VarStmt {
            name: name,
            typeName: Option::None,
            value: value,
        })
    }

    func parseDeferStmt(mut self) Result[DeferStmt, ParseError] {
        self.expectKeyword("defer")?
        var expr = self.parseExpr()?
        self.eatSymbol(";")
        Result::Ok(DeferStmt { expr: expr })
    }

    func parseTypedVarStmt(mut self, bool consumeSemicolon) Result[VarStmt, ParseError] {
        var segment = self.parseTokenSegment(Vec[string] { "=" })?
        var named = decodeNamedType(segment)?
        self.expectSymbol("=")?
        var value = self.parseExpr()?
        if consumeSemicolon {
            self.eatSymbol(";")
        }
        Result::Ok(VarStmt {
            name: named.name,
            typeName: Option::Some(named.typeName),
            value: value,
        })
    }

    func parseAssignStmt(mut self, bool consumeSemicolon) Result[AssignStmt, ParseError] {
        var name = self.expectIdent()?
        self.expectSymbol("=")?
        var value = self.parseExpr()?
        if consumeSemicolon {
            self.eatSymbol(";")
        }
        Result::Ok(AssignStmt {
            name: name,
            value: value,
        })
    }

    func parseIncrementStmt(mut self, bool consumeSemicolon) Result[IncrementStmt, ParseError] {
        var name = self.expectIdent()?
        self.expectSymbol("++")?
        if consumeSemicolon {
            self.eatSymbol(";")
        }
        Result::Ok(IncrementStmt {
            name: name,
        })
    }

    func parseCforStmt(mut self) Result[CForStmt, ParseError] {
        self.expectKeyword("for")?
        self.expectSymbol("(")?
        var init = self.parseForClauseStmt()?
        self.expectSymbol(";")?
        var condition = self.parseExpr()?
        self.expectSymbol(";")?
        var step = self.parseForClauseStmt()?
        self.expectSymbol(")")?
        var body = self.parseBlockExpr()?
        Result::Ok(CForStmt {
            init: box(init),
            condition: condition,
            step: box(step),
            body: body,
        })
    }

    func parseForClauseStmt(mut self) Result[Stmt, ParseError] {
        if self.atKeyword("var") {
            return Result::Ok(Stmt::Var(self.parseVarStmt(false)?))
        }
        if self.looksLikeShortVarStmt() {
            return Result::Ok(Stmt::Var(self.parseShortVarStmt(false)?))
        }
        if self.looksLikeTypedVarStmt() {
            return Result::Ok(Stmt::Var(self.parseTypedVarStmt(false)?))
        }
        if self.looksLikeIncrementStmt() {
            return Result::Ok(Stmt::Increment(self.parseIncrementStmt(false)?))
        }
        if self.looksLikeAssignmentStmt() {
            return Result::Ok(Stmt::Assign(self.parseAssignStmt(false)?))
        }
        Result::Err(self.errorHere("unexpected for clause"))
    }

    func parseReturnStmt(mut self) Result[ReturnStmt, ParseError] {
        self.expectKeyword("return")?
        if self.eatSymbol(";") {
            return Result::Ok(ReturnStmt {
                value: Option::None,
            })
        }
        var value = self.parseExpr()?
        self.eatSymbol(";")
        Result::Ok(ReturnStmt {
            value: Option::Some(value),
        })
    }

    func parseExpr(mut self) Result[Expr, ParseError] {
        if self.atKeyword("match") {
            return self.parseMatchExpr()
        }
        if self.atKeyword("if") {
            return self.parseIfExpr()
        }
        if self.atKeyword("while") {
            return self.parseWhileExpr()
        }
        if self.atKeyword("for") {
            return self.parseForExpr()
        }
        self.parseBinaryExpr(0)
    }

    func parseMatchExpr(mut self) Result[Expr, ParseError] {
        self.expectKeyword("match")?
        var subject = self.parseExpr()?
        self.expectSymbol("{")?
        var arms = Vec[MatchArm]()

        while !self.eatSymbol("}") {
            var pattern = self.parsePattern()?
            self.expectSymbol("=>")?
            var expr = self.parseExpr()?
            arms.push(MatchArm {
                pattern: pattern,
                expr: expr,
            })
            self.eatSymbol(",")
        }

        Result::Ok(Expr::Match(MatchExpr {
            subject: Box(subject),
            arms: arms,
            inferredType: Option::None,
        }))
    }

    func parseIfExpr(mut self) Result[Expr, ParseError] {
        self.expectKeyword("if")?
        var condition = self.parseExpr()?
        var thenBranch = self.parseBlockExpr()?
        var elseBranch =
            if self.eatKeyword("else") {
                if self.atKeyword("if") {
                    Option::Some(Box(self.parseIfExpr()?))
                } else {
                    Option::Some(Box(Expr::Block(self.parseBlockExpr()?)))
                }
            } else {
                Option::None
            }

        Result::Ok(Expr::If(IfExpr {
            condition: Box(condition),
            thenBranch: thenBranch,
            elseBranch: elseBranch,
            inferredType: Option::None,
        }))
    }

    func parseWhileExpr(mut self) Result[Expr, ParseError] {
        self.expectKeyword("while")?
        var condition = self.parseExpr()?
        var body = self.parseBlockExpr()?
        Result::Ok(Expr::While(WhileExpr {
            condition: Box(condition),
            body: body,
            inferredType: Option::None,
        }))
    }

    func parseForExpr(mut self) Result[Expr, ParseError] {
        self.expectKeyword("for")?
        var name = self.expectIdent()?
        self.expectKeyword("in")?
        var iterable = self.parseExpr()?
        var body = self.parseBlockExpr()?
        Result::Ok(Expr::For(ForExpr {
            name: name,
            iterable: Box(iterable),
            body: body,
            inferredType: Option::None,
        }))
    }

    func parsePattern(mut self) Result[Pattern, ParseError] {
        if self.eatIdentValue("_") {
            return Result::Ok(Pattern::Wildcard(WildcardPattern {}))
        }

        var path = self.parsePath()?
        if self.eatSymbol("(") {
            var args = Vec[Pattern]()
            if !self.atSymbol(")") {
                while true {
                    args.push(self.parsePattern()?)
                    if !self.eatSymbol(",") || self.atSymbol(")") {
                        break
                    }
                }
            }
            self.expectSymbol(")")?
            return Result::Ok(Pattern::Variant(VariantPattern {
                path: path,
                args: args,
            }))
        }

        if pathContainsDot(path) || startsWithUpper(path) {
            return Result::Ok(Pattern::Variant(VariantPattern {
                path: path,
                args: Vec[Pattern](),
            }))
        }

        Result::Ok(Pattern::Name(NamePattern { name: path }))
    }

    func parseBinaryExpr(mut self, int32 minPrecedence) Result[Expr, ParseError] {
        var expr = self.parseUnaryExpr()?
        while true {
            var token = self.peek()?
            var precedence = self.binaryPrecedence(token.value)
            if precedence < minPrecedence {
                break
            }
            var op = self.advance()?.value
            var rhs = self.parseBinaryExpr(precedence + 1)?
            expr = Expr::Binary(BinaryExpr {
                left: Box(expr),
                op: op,
                right: Box(rhs),
                inferredType: Option::None,
            })
        }
        Result::Ok(expr)
    }

    func parseUnaryExpr(mut self) Result[Expr, ParseError] {
        if self.eatSymbol("&") {
            var mutable = self.eatKeyword("mut")
            var target = self.parseUnaryExpr()?
            return Result::Ok(Expr::Borrow(BorrowExpr {
                target: Box(target),
                mutable: mutable,
                inferredType: Option::None,
            }))
        }
        self.parseCallExpr()
    }

    func parseCallExpr(mut self) Result[Expr, ParseError] {
        var expr = self.parsePrimaryExpr()?
        while true {
            if self.eatSymbol("(") {
                var args = Vec[Expr]()
                if !self.atSymbol(")") {
                    while true {
                        args.push(self.parseExpr()?)
                        if !self.eatSymbol(",") || self.atSymbol(")") {
                            break
                        }
                    }
                }
                self.expectSymbol(")")?
                expr = Expr::Call(CallExpr {
                    callee: Box(expr),
                    args: args,
                    inferredType: Option::None,
                })
                continue
            }
            if self.eatSymbol(".") {
                expr = Expr::Member(MemberExpr {
                    target: Box(expr),
                    member: self.expectIdent()?,
                    inferredType: Option::None,
                })
                continue
            }
            if self.eatSymbol("[") {
                var index = self.parseExpr()?
                self.expectSymbol("]")?
                expr = Expr::Index(IndexExpr {
                    target: Box(expr),
                    index: Box(index),
                    inferredType: Option::None,
                })
                continue
            }
            break
        }
        Result::Ok(expr)
    }

    func parsePrimaryExpr(mut self) Result[Expr, ParseError] {
        var token = self.peek()?
        if token.kind == TokenKind::Int {
            self.advance()?
            return Result::Ok(Expr::Int(IntExpr {
                value: token.value,
                inferredType: Option::None,
            }))
        }
        if token.kind == TokenKind::string {
            self.advance()?
            return Result::Ok(Expr::string(StringExpr {
                value: token.value,
                inferredType: Option::None,
            }))
        }
        if self.atKeyword("true") {
            self.advance()?
            return Result::Ok(Expr::Bool(BoolExpr {
                value: true,
                inferredType: Option::None,
            }))
        }
        if self.atKeyword("false") {
            self.advance()?
            return Result::Ok(Expr::Bool(BoolExpr {
                value: false,
                inferredType: Option::None,
            }))
        }
        if self.atSymbol("{") {
            return Result::Ok(Expr::Block(self.parseBlockExpr()?))
        }
        if self.eatSymbol("(") {
            var expr = self.parseExpr()?
            self.expectSymbol(")")?
            return Result::Ok(expr)
        }
        // composite literals: array literal syntax like []T{...}
        if self.atSymbol("[") {
            // consume bracket group (e.g., "[]")
            var bracket = self.parseBracketGroup()?
            var typeText = bracket
            // if there are more type tokens before '{', grab them
            var token = self.peek().unwrap()
            if token.kind != TokenKind::Symbol || token.value != "{" {
                var seg = self.parseTokenSegment(Vec[string] { "{" })?
                typeText = typeText + " " + joinTokenValues(seg)
            }
            self.expectSymbol("{")?
            var items = Vec[Expr]()
            if !self.atSymbol("}") {
                while true {
                    items.push(self.parseExpr()?)
                    if !self.eatSymbol(",") || self.atSymbol("}") {
                        break
                    }
                }
            }
            self.expectSymbol("}")?
            return Result::Ok(Expr::Array(ArrayLiteral { typeText: Option::Some(typeText.trim()), items: items }))
        }
        // map literal: map[K]V{ key: value, ... }
        if token.kind == TokenKind::Ident && token.value == "map" {
            // consume 'map'
            self.advance()?
            var bracket = self.parseBracketGroup()?
            var typeText = "map" + bracket
            // optional value type after bracket
            var token2 = self.peek().unwrap()
            if token2.kind == TokenKind::Ident || token2.kind == TokenKind::Symbol {
                var seg = self.parseTokenSegment(Vec[string] { "{" })?
                typeText = typeText + " " + joinTokenValues(seg)
            }
            self.expectSymbol("{")?
            var entries = Vec[MapEntry]()
            if !self.atSymbol("}") {
                while true {
                    var key = self.parseExpr()?
                    self.expectSymbol(":")?
                    var value = self.parseExpr()?
                    entries.push(MapEntry { key: key, value: value })
                    if !self.eatSymbol(",") || self.atSymbol("}") {
                        break
                    }
                }
            }
            self.expectSymbol("}")?
            return Result::Ok(Expr::Map(MapLiteral { typeText: Option::Some(typeText.trim()), entries: entries }))
        }
        Result::Ok(Expr::Name(NameExpr {
            name: self.expectIdent()?,
            inferredType: Option::None,
        }))
    }

    func binaryPrecedence(self, string op) int32 {
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

    func parseUsePath(mut self) Result[string, ParseError] {
        var parts = Vec[string]()
        parts.push(self.expectIdent()?)
        while self.eatSymbol(".") {
            if self.eatSymbol("{") {
                var members = Vec[string]()
                while !self.eatSymbol("}") {
                    var member = self.expectIdent()?
                    var text =
                        if self.eatKeyword("as") {
                            member + " as " + self.expectIdent()?
                        } else {
                            member
                        }
                    members.push(text)
                    self.eatSymbol(",")
                }
                return Result::Ok(joinStrings(parts, ".") + ".{" + joinStrings(members, ", ") + "}")
            }
            parts.push(self.expectIdent()?)
        }
        Result::Ok(joinStrings(parts, "."))
    }

    func parsePath(mut self) Result[string, ParseError] {
        var parts = Vec[string]()
        parts.push(self.expectIdent()?)
        while self.eatSymbol(".") {
            parts.push(self.expectIdent()?)
        }
        if self.atSymbol("[") {
            var last = parts.pop().unwrap()
            parts.push(last + self.parseBracketGroup()?)
        }
        Result::Ok(joinStrings(parts, "."))
    }

    func parseTypeText(mut self, Vec[string] stopValues) Result[string, ParseError] {
        var parts = Vec[string]()
        var bracket = 0
        var paren = 0

        while true {
            var token = self.peek()?
            if token.kind == TokenKind::Eof {
                break
            }
            if bracket == 0 && paren == 0 && containsString(stopValues, token.value) {
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

        Result::Ok(normalizeTypeText(joinStrings(parts, " ")))
    }

    func parseBracketGroup(mut self) Result[string, ParseError] {
        var parts = Vec[string]()
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
            joinStrings(parts, " ")
                .replace("[ ", "[")
                .replace(" ]", "]")
                .replace(" ,", ",")
        )
    }

    func at(self, TokenKind kind) bool {
        self.peek().unwrap().kind == kind
    }

    func atKeyword(self, string value) bool {
        var token = self.peek().unwrap()
        token.kind == TokenKind::Keyword && token.value == value
    }

    func atSymbol(self, string value) bool {
        var token = self.peek().unwrap()
        token.kind == TokenKind::Symbol && token.value == value
    }

    func atCforStart(self) bool {
        self.atKeyword("for") && self.peekAt(1).unwrap().kind == TokenKind::Symbol && self.peekAt(1).unwrap().value == "("
    }

    func looksLikeAssignmentStmt(self) bool {
        var first = self.peek().unwrap()
        var second = self.peekAt(1).unwrap()
        first.kind == TokenKind::Ident && second.kind == TokenKind::Symbol && second.value == "="
    }

    func looksLikeShortVarStmt(self) bool {
        var first = self.peek().unwrap()
        var second = self.peekAt(1).unwrap()
        first.kind == TokenKind::Ident && second.kind == TokenKind::Symbol && second.value == ":="
    }

    func looksLikeIncrementStmt(self) bool {
        var first = self.peek().unwrap()
        var second = self.peekAt(1).unwrap()
        first.kind == TokenKind::Ident && second.kind == TokenKind::Symbol && second.value == "++"
    }

    func looksLikeTypedVarStmt(self) bool {
        var offset = self.findTopLevelSymbolOffset("=")
        if offset <= 0 {
            return false
        }
        decodeNamedType(sliceTokens(self.tokens, self.index, self.index + offset)).isOk()
    }

    func eatKeyword(mut self, string value) bool {
        if self.atKeyword(value) {
            self.advance().unwrap()
            return true
        }
        false
    }

    func eatIdentValue(mut self, string value) bool {
        var token = self.peek().unwrap()
        if token.kind == TokenKind::Ident && token.value == value {
            self.advance().unwrap()
            return true
        }
        false
    }

    func eatSymbol(mut self, string value) bool {
        if self.atSymbol(value) {
            self.advance().unwrap()
            return true
        }
        false
    }

    func expectKeyword(mut self, string value) Result[Token, ParseError] {
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

    func expectSymbol(mut self, string value) Result[Token, ParseError] {
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

    func expectIdent(mut self) Result[string, ParseError] {
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

    func peek(self) Result[Token, ParseError] {
        self.peekAt(0)
    }

    func peekAt(self, int32 offset) Result[Token, ParseError] {
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

    func advance(mut self) Result[Token, ParseError] {
        var token = self.peek()?
        self.index = self.index + 1
        Result::Ok(token)
    }

    func errorHere(self, string message) ParseError {
        var token = self.peek().unwrap()
        ParseError {
            message: message,
            line: token.line,
            column: token.column,
        }
    }
}

impl Parser {
    func findTopLevelSymbolOffset(self, string value) int32 {
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
    Option[NamedType] receiver,
}

struct NamedType {
    string name,
    string typeName,
}

func decodeNamedType(Vec[Token] tokens) Result[NamedType, ParseError] {
    var colon = findTokenValue(tokens, ":")
    if colon >= 0 {
        var nameTokens = sliceTokens(tokens, 0, colon)
        var typeTokens = sliceTokens(tokens, colon + 1, len(tokens))
        return Result::Ok(NamedType {
            name: normalizeTypeText(joinTokenValues(nameTokens)),
            typeName: normalizeTypeText(joinTokenValues(typeTokens)),
        })
    }

    var split = findDeclNameIndex(tokens)
    if split <= 0 {
        return Result::Err(ParseError {
            message: "expected typed name",
            line: 0,
            column: 0,
        })
    }
    Result::Ok(NamedType {
        name: tokens[split].value,
        typeName: normalizeTypeText(joinTokenValues(sliceTokens(tokens, 0, split))),
    })
}

func sliceTokens(Vec[Token] tokens, int32 start, int32 end) Vec[Token] {
    var out = Vec[Token]()
    var i = start
    while i < end {
        out.push(tokens[i])
        i = i + 1
    }
    out
}

func joinTokenValues(Vec[Token] tokens) string {
    var parts = Vec[string]()
    for token in tokens {
        parts.push(token.value)
    }
    joinStrings(parts, " ")
}

func findTokenValue(Vec[Token] tokens, string value) int32 {
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

func findDeclNameIndex(Vec[Token] tokens) int32 {
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

func normalizeTypeText(string text) string {
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

func containsString(Vec[string] values, string target) bool {
    for value in values {
        if value == target {
            return true
        }
    }
    false
}

func joinStrings(Vec[string] values, string sep) string {
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

func pathContainsDot(string path) bool {
    var i = 0
    while i < len(path) {
        if charAt(path, i) == "." {
            return true
        }
        i = i + 1
    }
    false
}

func startsWithUpper(string text) bool {
    if text == "" {
        return false
    }
    var ch = charAt(text, 0)
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
