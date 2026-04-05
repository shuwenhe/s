package frontend

use std.option.Option
use std.prelude.box
use std.prelude.to_string
use std.vec.Vec

pub struct UseDecl {
    path: String,
    alias: Option[String],
}

pub struct Field {
    name: String,
    type_name: String,
    is_public: bool,
}

pub struct Param {
    name: String,
    type_name: String,
}

pub struct FunctionSig {
    name: String,
    generics: Vec[String],
    params: Vec[Param],
    return_type: Option[String],
}

pub struct NamePattern {
    name: String,
}

pub struct WildcardPattern {}

pub struct VariantPattern {
    path: String,
    args: Vec[Pattern],
}

pub enum Pattern {
    Name(NamePattern),
    Wildcard(WildcardPattern),
    Variant(VariantPattern),
}

pub struct IntExpr {
    value: String,
    inferred_type: Option[String],
}

pub struct StringExpr {
    value: String,
    inferred_type: Option[String],
}

pub struct BoolExpr {
    value: bool,
    inferred_type: Option[String],
}

pub struct NameExpr {
    name: String,
    inferred_type: Option[String],
}

pub struct BorrowExpr {
    target: Box[Expr],
    mutable: bool,
    inferred_type: Option[String],
}

pub struct BinaryExpr {
    left: Box[Expr],
    op: String,
    right: Box[Expr],
    inferred_type: Option[String],
}

pub struct MemberExpr {
    target: Box[Expr],
    member: String,
    inferred_type: Option[String],
}

pub struct IndexExpr {
    target: Box[Expr],
    index: Box[Expr],
    inferred_type: Option[String],
}

pub struct CallExpr {
    callee: Box[Expr],
    args: Vec[Expr],
    inferred_type: Option[String],
}

pub struct MatchArm {
    pattern: Pattern,
    expr: Expr,
}

pub struct MatchExpr {
    subject: Box[Expr],
    arms: Vec[MatchArm],
    inferred_type: Option[String],
}

pub struct IfExpr {
    condition: Box[Expr],
    then_branch: BlockExpr,
    else_branch: Option[Box[Expr]],
    inferred_type: Option[String],
}

pub struct WhileExpr {
    condition: Box[Expr],
    body: BlockExpr,
    inferred_type: Option[String],
}

pub struct ForExpr {
    name: String,
    iterable: Box[Expr],
    body: BlockExpr,
    inferred_type: Option[String],
}

pub struct BlockExpr {
    statements: Vec[Stmt],
    final_expr: Option[Expr],
    inferred_type: Option[String],
}

pub enum Expr {
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

pub struct VarStmt {
    name: String,
    type_name: Option[String],
    value: Expr,
}

pub struct ReturnStmt {
    value: Option[Expr],
}

pub struct ExprStmt {
    expr: Expr,
}

pub enum Stmt {
    Var(VarStmt),
    Return(ReturnStmt),
    Expr(ExprStmt),
}

pub struct FunctionDecl {
    sig: FunctionSig,
    body: Option[BlockExpr],
    is_public: bool,
}

pub struct StructDecl {
    name: String,
    generics: Vec[String],
    fields: Vec[Field],
    is_public: bool,
}

pub struct EnumVariant {
    name: String,
    payload: Option[String],
}

pub struct EnumDecl {
    name: String,
    generics: Vec[String],
    variants: Vec[EnumVariant],
    is_public: bool,
}

pub struct TraitDecl {
    name: String,
    generics: Vec[String],
    methods: Vec[FunctionSig],
    is_public: bool,
}

pub struct ImplDecl {
    target: String,
    trait_name: Option[String],
    generics: Vec[String],
    methods: Vec[FunctionDecl],
}

pub enum Item {
    Function(FunctionDecl),
    Struct(StructDecl),
    Enum(EnumDecl),
    Trait(TraitDecl),
    Impl(ImplDecl),
}

pub struct SourceFile {
    package: String,
    uses: Vec[UseDecl],
    items: Vec[Item],
}

pub fn dump_source_file(source: SourceFile) -> String {
    let lines = Vec[String]()
    lines.push("package " + source.package)
    for use_decl in source.uses {
        let text =
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

pub fn append_item_dump(lines: Vec[String], item: Item) -> () {
    match item {
        Item::Function(value) => append_lines(lines, dump_function(value, "")),
        Item::Struct(value) => append_lines(lines, dump_struct(value)),
        Item::Enum(value) => append_lines(lines, dump_enum(value)),
        Item::Trait(value) => append_lines(lines, dump_trait(value)),
        Item::Impl(value) => append_lines(lines, dump_impl(value)),
    }
}

pub fn fmt_generics(generics: Vec[String]) -> String {
    if len(generics) == 0 {
        return ""
    }
    "[" + join_with(generics, ", ") + "]"
}

pub fn dump_function(item: FunctionDecl, indent: String) -> Vec[String] {
    let lines = Vec[String]()
    let params = Vec[String]()
    for param in item.sig.params {
        params.push(param.name + ": " + param.type_name)
    }
    let ret =
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

pub fn dump_struct(item: StructDecl) -> Vec[String] {
    let lines = Vec[String]()
    lines.push("struct " + item.name + fmt_generics(item.generics))
    for field in item.fields {
        lines.push("  " + field.name + ": " + field.type_name)
    }
    lines
}

pub fn dump_enum(item: EnumDecl) -> Vec[String] {
    let lines = Vec[String]()
    lines.push("enum " + item.name + fmt_generics(item.generics))
    for variant in item.variants {
        match variant.payload {
            Option::Some(payload) => lines.push("  " + variant.name + "(" + payload + ")"),
            Option::None => lines.push("  " + variant.name),
        }
    }
    lines
}

pub fn dump_trait(item: TraitDecl) -> Vec[String] {
    let lines = Vec[String]()
    lines.push("trait " + item.name + fmt_generics(item.generics))
    for method in item.methods {
        let params = Vec[String]()
        for param in method.params {
            params.push(param.name + ": " + param.type_name)
        }
        let ret =
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

pub fn dump_impl(item: ImplDecl) -> Vec[String] {
    let lines = Vec[String]()
    let head =
        match item.trait_name {
            Option::Some(name) => name + " for " + item.target,
            Option::None => item.target,
        }
    let title = replace_once("impl " + fmt_generics(item.generics) + " " + head, "impl  ", "impl ")
    lines.push(title)
    for method in item.methods {
        append_lines(lines, dump_function(method, "  "))
    }
    lines
}

pub fn dump_block(block: BlockExpr, indent: String) -> Vec[String] {
    let lines = Vec[String]()
    for stmt in block.statements {
        append_lines(lines, dump_stmt(stmt, indent))
    }
    match block.final_expr {
        Option::Some(expr) => lines.push(indent + "final " + dump_expr(expr)),
        Option::None => (),
    }
    lines
}

pub fn dump_stmt(stmt: Stmt, indent: String) -> Vec[String] {
    match stmt {
        Stmt::Let(value) => {
            let text =
                match value.type_name {
                    Option::Some(type_name) => indent + "let " + value.name + ": " + type_name + " = " + dump_expr(value.value),
                    Option::None => indent + "let " + value.name + " = " + dump_expr(value.value),
                }
            single_line(text)
        }
        Stmt::Return(value) => {
            let text =
                match value.value {
                    Option::Some(expr) => indent + "return " + dump_expr(expr),
                    Option::None => indent + "return ()",
                }
            single_line(text)
        }
        Stmt::Expr(value) => single_line(indent + "expr " + dump_expr(value.expr)),
    }
}

pub fn dump_expr(expr: Expr) -> String {
    match expr {
        Expr::Int(value) => value.value,
        Expr::String(value) => value.value,
        Expr::Bool(value) => if value.value { "true" } else { "false" },
        Expr::Name(value) => value.name,
        Expr::Borrow(value) => {
            let prefix = if value.mutable { "&mut " } else { "&" }
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

pub fn dump_if_expr(value: IfExpr) -> String {
    let text = "if " + dump_expr(value.condition.value) + " {...}"
    match value.else_branch {
        Option::Some(expr) => text + " else " + dump_expr(expr.value),
        Option::None => text,
    }
}

pub fn dump_pattern(pattern: Pattern) -> String {
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

pub fn join_exprs(values: Vec[Expr]) -> String {
    let parts = Vec[String]()
    for value in values {
        parts.push(dump_expr(value))
    }
    join_with(parts, ", ")
}

pub fn join_patterns(values: Vec[Pattern]) -> String {
    let parts = Vec[String]()
    for value in values {
        parts.push(dump_pattern(value))
    }
    join_with(parts, ", ")
}

pub fn join_match_arms(values: Vec[MatchArm]) -> String {
    let parts = Vec[String]()
    for value in values {
        parts.push(dump_pattern(value.pattern) + " => " + dump_expr(value.expr))
    }
    join_with(parts, "; ")
}

pub fn append_lines(dest: Vec[String], source: Vec[String]) -> () {
    for line in source {
        dest.push(line)
    }
}

pub fn single_line(text: String) -> Vec[String] {
    let lines = Vec[String]()
    lines.push(text)
    lines
}

pub fn join_lines(lines: Vec[String]) -> String {
    join_with(lines, "\n")
}

pub fn join_with(values: Vec[String], sep: String) -> String {
    let out = ""
    let first = true
    for value in values {
        if !first {
            out = out + sep
        }
        out = out + value
        first = false
    }
    out
}

pub fn replace_once(text: String, from: String, to: String) -> String {
    text
}
