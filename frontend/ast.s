package frontend

use std.option.Option
use std.prelude.box
use std.prelude.to_string
use std.vec.Vec

struct UseDecl {
    path: String,
    alias: Option[String],
}

struct Field {
    name: String,
    type_name: String,
    is_public: bool,
}

struct Param {
    name: String,
    type_name: String,
}

struct FunctionSig {
    name: String,
    generics: Vec[String],
    params: Vec[Param],
    return_type: Option[String],
}

struct NamePattern {
    name: String,
}

struct WildcardPattern {}

struct VariantPattern {
    path: String,
    args: Vec[Pattern],
}

enum Pattern {
    Name(NamePattern),
    Wildcard(WildcardPattern),
    Variant(VariantPattern),
}

struct IntExpr {
    value: String,
    inferred_type: Option[String],
}

struct StringExpr {
    value: String,
    inferred_type: Option[String],
}

struct BoolExpr {
    value: bool,
    inferred_type: Option[String],
}

struct NameExpr {
    name: String,
    inferred_type: Option[String],
}

struct BorrowExpr {
    target: Box[Expr],
    mutable: bool,
    inferred_type: Option[String],
}

struct BinaryExpr {
    left: Box[Expr],
    op: String,
    right: Box[Expr],
    inferred_type: Option[String],
}

struct MemberExpr {
    target: Box[Expr],
    member: String,
    inferred_type: Option[String],
}

struct IndexExpr {
    target: Box[Expr],
    index: Box[Expr],
    inferred_type: Option[String],
}

struct CallExpr {
    callee: Box[Expr],
    args: Vec[Expr],
    inferred_type: Option[String],
}

struct MatchArm {
    pattern: Pattern,
    expr: Expr,
}

struct MatchExpr {
    subject: Box[Expr],
    arms: Vec[MatchArm],
    inferred_type: Option[String],
}

struct IfExpr {
    condition: Box[Expr],
    then_branch: BlockExpr,
    else_branch: Option[Box[Expr]],
    inferred_type: Option[String],
}

struct WhileExpr {
    condition: Box[Expr],
    body: BlockExpr,
    inferred_type: Option[String],
}

struct ForExpr {
    name: String,
    iterable: Box[Expr],
    body: BlockExpr,
    inferred_type: Option[String],
}

struct BlockExpr {
    statements: Vec[Stmt],
    final_expr: Option[Expr],
    inferred_type: Option[String],
}

enum Expr {
    Int(IntExpr),
    String(StringExpr),
    Bool(BoolExpr),
    Name(NameExpr),
    Borrow(BorrowExpr),
    Binary(BinaryExpr),
    Member(MemberExpr),
    Index(IndexExpr),
    Call(CallExpr),
    Match(MatchExpr),
    If(IfExpr),
    While(WhileExpr),
    For(ForExpr),
    Block(BlockExpr),
}

struct VarStmt {
    name: String,
    type_name: Option[String],
    value: Expr,
}

struct ReturnStmt {
    value: Option[Expr],
}

struct ExprStmt {
    expr: Expr,
}

enum Stmt {
    Var(VarStmt),
    Return(ReturnStmt),
    Expr(ExprStmt),
}

struct FunctionDecl {
    sig: FunctionSig,
    body: Option[BlockExpr],
    is_public: bool,
}

struct StructDecl {
    name: String,
    generics: Vec[String],
    fields: Vec[Field],
    is_public: bool,
}

struct EnumVariant {
    name: String,
    payload: Option[String],
}

struct EnumDecl {
    name: String,
    generics: Vec[String],
    variants: Vec[EnumVariant],
    is_public: bool,
}

struct TraitDecl {
    name: String,
    generics: Vec[String],
    methods: Vec[FunctionSig],
    is_public: bool,
}

struct ImplDecl {
    target: String,
    trait_name: Option[String],
    generics: Vec[String],
    methods: Vec[FunctionDecl],
}

enum Item {
    Function(FunctionDecl),
    Struct(StructDecl),
    Enum(EnumDecl),
    Trait(TraitDecl),
    Impl(ImplDecl),
}

struct SourceFile {
    package: String,
    uses: Vec[UseDecl],
    items: Vec[Item],
}

fn dump_source_file(source: SourceFile) -> String {
    var lines = Vec[String]()
    lines.push("package " + source.package)
    for use_decl in source.uses {
        var text =
            match use_decl.alias {
                Option::Some(alias) => "use " + use_decl.path + " as " + alias,
                Option::None => "use " + use_decl.path,
            }
        lines.push(text)
    }
    for item in source.items {
        append_item_dump(lines, item)
    }
    join_lines(lines)
}

fn append_item_dump(lines: Vec[String], item: Item) -> () {
    match item {
        Item::Function(value) => append_lines(lines, dump_function(value, "")),
        Item::Struct(value) => append_lines(lines, dump_struct(value)),
        Item::Enum(value) => append_lines(lines, dump_enum(value)),
        Item::Trait(value) => append_lines(lines, dump_trait(value)),
        Item::Impl(value) => append_lines(lines, dump_impl(value)),
    }
}

fn fmt_generics(generics: Vec[String]) -> String {
    if len(generics) == 0 {
        return ""
    }
    "[" + join_with(generics, ", ") + "]"
}

fn dump_function(item: FunctionDecl, indent: String) -> Vec[String] {
    var lines = Vec[String]()
    var params = Vec[String]()
    for param in item.sig.params {
        params.push(param.name + ": " + param.type_name)
    }
    var ret =
        match item.sig.return_type {
            Option::Some(value) => " -> " + value,
            Option::None => "",
        }
    lines.push(
        indent
            + "fn "
            + item.sig.name
            + fmt_generics(item.sig.generics)
            + "("
            + join_with(params, ", ")
            + ")"
            + ret
    )
    match item.body {
        Option::Some(body) => append_lines(lines, dump_block(body, indent + "  ")),
        Option::None => (),
    }
    lines
}

fn dump_struct(item: StructDecl) -> Vec[String] {
    var lines = Vec[String]()
    lines.push("struct " + item.name + fmt_generics(item.generics))
    for field in item.fields {
        lines.push("  " + field.name + ": " + field.type_name)
    }
    lines
}

fn dump_enum(item: EnumDecl) -> Vec[String] {
    var lines = Vec[String]()
    lines.push("enum " + item.name + fmt_generics(item.generics))
    for variant in item.variants {
        match variant.payload {
            Option::Some(payload) => lines.push("  " + variant.name + "(" + payload + ")"),
            Option::None => lines.push("  " + variant.name),
        }
    }
    lines
}

fn dump_trait(item: TraitDecl) -> Vec[String] {
    var lines = Vec[String]()
    lines.push("trait " + item.name + fmt_generics(item.generics))
    for method in item.methods {
        var params = Vec[String]()
        for param in method.params {
            params.push(param.name + ": " + param.type_name)
        }
        var ret =
            match method.return_type {
                Option::Some(value) => " -> " + value,
                Option::None => "",
            }
        lines.push(
            "  fn "
                + method.name
                + fmt_generics(method.generics)
                + "("
                + join_with(params, ", ")
                + ")"
                + ret
        )
    }
    lines
}

fn dump_impl(item: ImplDecl) -> Vec[String] {
    var lines = Vec[String]()
    var head =
        match item.trait_name {
            Option::Some(name) => name + " for " + item.target,
            Option::None => item.target,
        }
    var title = replace_once("impl " + fmt_generics(item.generics) + " " + head, "impl  ", "impl ")
    lines.push(title)
    for method in item.methods {
        append_lines(lines, dump_function(method, "  "))
    }
    lines
}

fn dump_block(block: BlockExpr, indent: String) -> Vec[String] {
    var lines = Vec[String]()
    for stmt in block.statements {
        append_lines(lines, dump_stmt(stmt, indent))
    }
    match block.final_expr {
        Option::Some(expr) => lines.push(indent + "final " + dump_expr(expr)),
        Option::None => (),
    }
    lines
}

fn dump_stmt(stmt: Stmt, indent: String) -> Vec[String] {
    match stmt {
        Stmt::Var(value) => {
            var text =
                match value.type_name {
                    Option::Some(type_name) => indent + "var " + value.name + ": " + type_name + " = " + dump_expr(value.value),
                    Option::None => indent + "var " + value.name + " = " + dump_expr(value.value),
                }
            single_line(text)
        }
        Stmt::Return(value) => {
            var text =
                match value.value {
                    Option::Some(expr) => indent + "return " + dump_expr(expr),
                    Option::None => indent + "return ()",
                }
            single_line(text)
        }
        Stmt::Expr(value) => single_line(indent + "expr " + dump_expr(value.expr)),
    }
}

fn dump_expr(expr: Expr) -> String {
    match expr {
        Expr::Int(value) => value.value,
        Expr::String(value) => value.value,
        Expr::Bool(value) => if value.value { "true" } else { "false" },
        Expr::Name(value) => value.name,
        Expr::Borrow(value) => {
            var prefix = if value.mutable { "&mut " } else { "&" }
            prefix + dump_expr(value.target.value)
        }
        Expr::Binary(value) => "(" + dump_expr(value.left.value) + " " + value.op + " " + dump_expr(value.right.value) + ")",
        Expr::Member(value) => dump_expr(value.target.value) + "." + value.member,
        Expr::Index(value) => dump_expr(value.target.value) + "[" + dump_expr(value.index.value) + "]",
        Expr::Call(value) => "call " + dump_expr(value.callee.value) + "(" + join_exprs(value.args) + ")",
        Expr::Match(value) => "match " + dump_expr(value.subject.value) + " { " + join_match_arms(value.arms) + " }",
        Expr::If(value) => dump_if_expr(value),
        Expr::While(value) => "while " + dump_expr(value.condition.value) + " {...}",
        Expr::For(value) => "for " + value.name + " in " + dump_expr(value.iterable.value) + " {...}",
        Expr::Block(_) => "{...}",
    }
}

fn dump_if_expr(value: IfExpr) -> String {
    var text = "if " + dump_expr(value.condition.value) + " {...}"
    match value.else_branch {
        Option::Some(expr) => text + " else " + dump_expr(expr.value),
        Option::None => text,
    }
}

fn dump_pattern(pattern: Pattern) -> String {
    match pattern {
        Pattern::Name(value) => value.name,
        Pattern::Wildcard(_) => "_",
        Pattern::Variant(value) => {
            if len(value.args) == 0 {
                return value.path
            }
            value.path + "(" + join_patterns(value.args) + ")"
        }
    }
}

fn join_exprs(values: Vec[Expr]) -> String {
    var parts = Vec[String]()
    for value in values {
        parts.push(dump_expr(value))
    }
    join_with(parts, ", ")
}

fn join_patterns(values: Vec[Pattern]) -> String {
    var parts = Vec[String]()
    for value in values {
        parts.push(dump_pattern(value))
    }
    join_with(parts, ", ")
}

fn join_match_arms(values: Vec[MatchArm]) -> String {
    var parts = Vec[String]()
    for value in values {
        parts.push(dump_pattern(value.pattern) + " => " + dump_expr(value.expr))
    }
    join_with(parts, "; ")
}

fn append_lines(dest: Vec[String], source: Vec[String]) -> () {
    for line in source {
        dest.push(line)
    }
}

fn single_line(text: String) -> Vec[String] {
    var lines = Vec[String]()
    lines.push(text)
    lines
}

fn join_lines(lines: Vec[String]) -> String {
    join_with(lines, "\n")
}

fn join_with(values: Vec[String], sep: String) -> String {
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

fn replace_once(text: String, from: String, to: String) -> String {
    text
}
