package s

use std.option.Option
use std.prelude.box
use std.prelude.to_string
use std.vec.Vec

struct UseDecl {
    String path,
    Option[String] alias,
}

struct Field {
    String name,
    String type_name,
    bool is_public,
}

struct Param {
    String name,
    String type_name,
}

struct FunctionSig {
    String name,
    Vec[String] generics,
    Vec[Param] params,
    Option[String] return_type,
}

struct NamePattern {
    String name,
}

struct WildcardPattern {}

struct VariantPattern {
    String path,
    Vec[Pattern] args,
}

enum Pattern {
    Name(NamePattern),
    Wildcard(WildcardPattern),
    Variant(VariantPattern),
}

struct IntExpr {
    String value,
    Option[String] inferred_type,
}

struct StringExpr {
    String value,
    Option[String] inferred_type,
}

struct BoolExpr {
    bool value,
    Option[String] inferred_type,
}

struct NameExpr {
    String name,
    Option[String] inferred_type,
}

struct BorrowExpr {
    Box[Expr] target,
    bool mutable,
    Option[String] inferred_type,
}

struct BinaryExpr {
    Box[Expr] left,
    String op,
    Box[Expr] right,
    Option[String] inferred_type,
}

struct MemberExpr {
    Box[Expr] target,
    String member,
    Option[String] inferred_type,
}

struct IndexExpr {
    Box[Expr] target,
    Box[Expr] index,
    Option[String] inferred_type,
}

struct CallExpr {
    Box[Expr] callee,
    Vec[Expr] args,
    Option[String] inferred_type,
}

struct MatchArm {
    Pattern pattern,
    Expr expr,
}

struct MatchExpr {
    Box[Expr] subject,
    Vec[MatchArm] arms,
    Option[String] inferred_type,
}

struct IfExpr {
    Box[Expr] condition,
    BlockExpr then_branch,
    Option[Box[Expr]] else_branch,
    Option[String] inferred_type,
}

struct WhileExpr {
    Box[Expr] condition,
    BlockExpr body,
    Option[String] inferred_type,
}

struct ForExpr {
    String name,
    Box[Expr] iterable,
    BlockExpr body,
    Option[String] inferred_type,
}

struct BlockExpr {
    Vec[Stmt] statements,
    Option[Expr] final_expr,
    Option[String] inferred_type,
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
    String name,
    Option[String] type_name,
    Expr value,
}

struct AssignStmt {
    String name,
    Expr value,
}

struct IncrementStmt {
    String name,
}

struct CForStmt {
    Box[Stmt] init,
    Expr condition,
    Box[Stmt] step,
    BlockExpr body,
}

struct ReturnStmt {
    Option[Expr] value,
}

struct ExprStmt {
    Expr expr,
}

struct DeferStmt {
    Expr expr,
}

enum Stmt {
    Var(VarStmt),
    Assign(AssignStmt),
    Increment(IncrementStmt),
    CFor(CForStmt),
    Return(ReturnStmt),
    Expr(ExprStmt),
    Defer(DeferStmt),
}

struct FunctionDecl {
    FunctionSig sig,
    Option[BlockExpr] body,
    bool is_public,
}

struct StructDecl {
    String name,
    Vec[String] generics,
    Vec[Field] fields,
    bool is_public,
}

struct EnumVariant {
    String name,
    Option[String] payload,
}

struct EnumDecl {
    String name,
    Vec[String] generics,
    Vec[EnumVariant] variants,
    bool is_public,
}

struct TraitDecl {
    String name,
    Vec[String] generics,
    Vec[FunctionSig] methods,
    bool is_public,
}

struct ImplDecl {
    String target,
    Option[String] trait_name,
    Vec[String] generics,
    Vec[FunctionDecl] methods,
}

enum Item {
    Function(FunctionDecl),
    Struct(StructDecl),
    Enum(EnumDecl),
    Trait(TraitDecl),
    Impl(ImplDecl),
}

struct SourceFile {
    String package,
    Vec[UseDecl] uses,
    Vec[Item] items,
}

func dump_source_file(SourceFile source) -> String {
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

func append_item_dump(Vec[String] lines, Item item) -> () {
    match item {
        Item::Function(value) => append_lines(lines, dump_function(value, "")),
        Item::Struct(value) => append_lines(lines, dump_struct(value)),
        Item::Enum(value) => append_lines(lines, dump_enum(value)),
        Item::Trait(value) => append_lines(lines, dump_trait(value)),
        Item::Impl(value) => append_lines(lines, dump_impl(value)),
    }
}

func fmt_generics(Vec[String] generics) -> String {
    if len(generics) == 0 {
        return ""
    }
    "[" + join_with(generics, ", ") + "]"
}

func dump_function(FunctionDecl item, String indent) -> Vec[String] {
    var lines = Vec[String]()
    var params = Vec[String]()
    for param in item.sig.params {
        params.push(param.type_name + " " + param.name)
    }
    var ret =
        match item.sig.return_type {
            Option::Some(value) => " -> " + value,
            Option::None => "",
        }
    lines.push(
        indent
            + "func "
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

func dump_struct(StructDecl item) -> Vec[String] {
    var lines = Vec[String]()
    lines.push("struct " + item.name + fmt_generics(item.generics))
    for field in item.fields {
        lines.push("  " + field.type_name + " " + field.name)
    }
    lines
}

func dump_enum(EnumDecl item) -> Vec[String] {
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

func dump_trait(TraitDecl item) -> Vec[String] {
    var lines = Vec[String]()
    lines.push("trait " + item.name + fmt_generics(item.generics))
    for method in item.methods {
        var params = Vec[String]()
        for param in method.params {
            params.push(param.type_name + " " + param.name)
        }
        var ret =
            match method.return_type {
                Option::Some(value) => " -> " + value,
                Option::None => "",
            }
        lines.push(
            "  func "
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

func dump_impl(ImplDecl item) -> Vec[String] {
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

func dump_block(BlockExpr block, String indent) -> Vec[String] {
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

func dump_stmt(Stmt stmt, String indent) -> Vec[String] {
    match stmt {
        Stmt::Var(value) => {
            var text =
                match value.type_name {
                    Option::Some(type_name) => indent + type_name + " " + value.name + " = " + dump_expr(value.value),
                    Option::None => indent + "var " + value.name + " = " + dump_expr(value.value),
            }
            single_line(text)
        }
        Stmt::Assign(value) => {
            single_line(indent + value.name + " = " + dump_expr(value.value))
        }
        Stmt::Increment(value) => {
            single_line(indent + value.name + "++")
        }
        Stmt::CFor(value) => {
            var lines = Vec[String]()
            lines.push(
                indent
                    + "for ("
                    + dump_for_clause(value.init.value)
                    + "; "
                    + dump_expr(value.condition)
                    + "; "
                    + dump_for_clause(value.step.value)
                    + ")"
            )
            append_lines(lines, dump_block(value.body, indent + "  "))
            lines
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
        Stmt::Defer(value) => single_line(indent + "defer " + dump_expr(value.expr)),
    }
}

func dump_for_clause(Stmt stmt) -> String {
    match stmt {
        Stmt::Var(value) => {
            match value.type_name {
                Option::Some(type_name) => type_name + " " + value.name + " = " + dump_expr(value.value),
                Option::None => "var " + value.name + " = " + dump_expr(value.value),
            }
        }
        Stmt::Assign(value) => value.name + " = " + dump_expr(value.value),
        Stmt::Increment(value) => value.name + "++",
        Stmt::Expr(value) => dump_expr(value.expr),
        Stmt::Return(_) => "return",
        Stmt::CFor(_) => "for (...)",
    }
}

func dump_expr(Expr expr) -> String {
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

func dump_if_expr(IfExpr value) -> String {
    var text = "if " + dump_expr(value.condition.value) + " {...}"
    match value.else_branch {
        Option::Some(expr) => text + " else " + dump_expr(expr.value),
        Option::None => text,
    }
}

func dump_pattern(Pattern pattern) -> String {
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

func join_exprs(Vec[Expr] values) -> String {
    var parts = Vec[String]()
    for value in values {
        parts.push(dump_expr(value))
    }
    join_with(parts, ", ")
}

func join_patterns(Vec[Pattern] values) -> String {
    var parts = Vec[String]()
    for value in values {
        parts.push(dump_pattern(value))
    }
    join_with(parts, ", ")
}

func join_match_arms(Vec[MatchArm] values) -> String {
    var parts = Vec[String]()
    for value in values {
        parts.push(dump_pattern(value.pattern) + " => " + dump_expr(value.expr))
    }
    join_with(parts, "; ")
}

func append_lines(Vec[String] dest, Vec[String] source) -> () {
    for line in source {
        dest.push(line)
    }
}

func single_line(String text) -> Vec[String] {
    var lines = Vec[String]()
    lines.push(text)
    lines
}

func join_lines(Vec[String] lines) -> String {
    join_with(lines, "\n")
}

func join_with(Vec[String] values, String sep) -> String {
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

func replace_once(String text, String from, String to) -> String {
    text
}
