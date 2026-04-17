package s

use std.option.Option
use std.prelude.box
use std.prelude.toString
use std.vec.Vec

struct UseDecl {
    string path,
    Option[string] alias,
}

struct Field {
    string name,
    string typeName,
    bool isPublic,
}

struct Param {
    string name,
    string typeName,
}

struct FunctionSig {
    string name,
    Vec[string] generics,
    Vec[Param] params,
    Option[string] returnType,
}

struct NamePattern {
    string name,
}

struct WildcardPattern {}

struct VariantPattern {
    string path,
    Vec[Pattern] args,
}

struct LiteralPattern {
    Expr value,
}

enum Pattern {
    Name(NamePattern),
    Wildcard(WildcardPattern),
    Variant(VariantPattern),
    Literal(LiteralPattern),
}

struct IntExpr {
    string value,
    Option[string] inferredType,
}

struct StringExpr {
    string value,
    Option[string] inferredType,
}

struct BoolExpr {
    bool value,
    Option[string] inferredType,
}

struct NameExpr {
    string name,
    Option[string] inferredType,
}

struct BorrowExpr {
    Box[Expr] target,
    bool mutable,
    Option[string] inferredType,
}

struct BinaryExpr {
    Box[Expr] left,
    string op,
    Box[Expr] right,
    Option[string] inferredType,
}

struct MemberExpr {
    Box[Expr] target,
    string member,
    Option[string] inferredType,
}

struct IndexExpr {
    Box[Expr] target,
    Box[Expr] index,
    Option[string] inferredType,
}

struct CallExpr {
    Box[Expr] callee,
    Vec[Expr] args,
    Option[string] inferredType,
}

struct SwitchArm {
    Pattern pattern,
    Expr expr,
}

struct SwitchExpr {
    Box[Expr] subject,
    Vec[SwitchArm] arms,
    Option[string] inferredType,
}

struct IfExpr {
    Box[Expr] condition,
    BlockExpr thenBranch,
    Option[Box[Expr]] elseBranch,
    Option[string] inferredType,
}

struct WhileExpr {
    Box[Expr] condition,
    BlockExpr body,
    Option[string] inferredType,
}

struct ForExpr {
    Vec[string] names,
    bool declare,
    Box[Expr] iterable,
    BlockExpr body,
    Option[string] inferredType,
}

struct BlockExpr {
    Vec[Stmt] statements,
    Option[Expr] finalExpr,
    Option[string] inferredType,
}

struct ArrayLiteral {
    Option[string] typeText,
    Vec[Expr] items,
}

struct MapEntry {
    Expr key,
    Expr value,
}

struct MapLiteral {
    Option[string] typeText,
    Vec[MapEntry] entries,
}

enum Expr {
    Int(IntExpr),
    string(StringExpr),
    Bool(BoolExpr),
    Name(NameExpr),
    Borrow(BorrowExpr),
    Binary(BinaryExpr),
    Member(MemberExpr),
    Index(IndexExpr),
    Call(CallExpr),
    Switch(SwitchExpr),
    If(IfExpr),
    While(WhileExpr),
    For(ForExpr),
    Block(BlockExpr),
    Array(ArrayLiteral),
    Map(MapLiteral),
}

struct VarStmt {
    string name,
    Option[string] typeName,
    Expr value,
}

struct AssignStmt {
    string name,
    Expr value,
}

struct IncrementStmt {
    string name,
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
    bool isPublic,
}

struct StructDecl {
    string name,
    Vec[string] generics,
    Vec[Field] fields,
    bool isPublic,
}

struct EnumVariant {
    string name,
    Option[string] payload,
}

struct EnumDecl {
    string name,
    Vec[string] generics,
    Vec[EnumVariant] variants,
    bool isPublic,
}

struct TraitDecl {
    string name,
    Vec[string] generics,
    Vec[FunctionSig] methods,
    bool isPublic,
}

struct ImplDecl {
    string target,
    Option[string] traitName,
    Vec[string] generics,
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
    string pkg,
    Vec[UseDecl] uses,
    Vec[Item] items,
}

func dumpSourceFile(SourceFile source) string {
    var lines = Vec[string]()
    lines.push("package " + source.pkg);
    var ui = 0
    while ui < source.uses.len() {
        var useDecl = source.uses[ui]
        var text =
            switch useDecl.alias {
                Option.Some(alias) : "use " + useDecl.path + " as " + alias,
                Option.None : "use " + useDecl.path,
            }
        lines.push(text);
        ui = ui + 1
    }
    var ii = 0
    while ii < source.items.len() {
        var item = source.items[ii]
        appendItemDump(lines, item);
        ii = ii + 1
    }
    joinLines(lines)
}

func appendItemDump(Vec[string] lines, Item item) () {
    switch item {
        Item.Function(value) : appendLines(lines, dumpFunction(value, "")),
        Item.Struct(value) : appendLines(lines, dumpStruct(value)),
        Item.Enum(value) : appendLines(lines, dumpEnum(value)),
        Item.Trait(value) : appendLines(lines, dumpTrait(value)),
        Item.Impl(value) : appendLines(lines, dumpImpl(value)),
    }
}

func fmtGenerics(Vec[string] generics) string {
    if len(generics) == 0 {
        return ""
    }
    "[" + joinWith(generics, ", ") + "]"
}

func dumpFunction(FunctionDecl item, string indent) Vec[string] {
    var lines = Vec[string]()
    var params = Vec[string]()
    var _pi = 0
    while _pi < item.sig.params.len() {
        var param = item.sig.params[_pi]
        params.push(param.typeName + " " + param.name)
        _pi = _pi + 1
    }
    var ret =
        switch item.sig.returnType {
            Option.Some(value) : " -> " + value,
            Option.None : "",
        }
    var prefix = if item.isPublic { "pub " } else { "" }
    lines.push(
        indent
            + prefix
            + "func "
            + item.sig.name
            + fmtGenerics(item.sig.generics)
            + "("
            + joinWith(params, ", ")
            + ")"
            + ret
    )
    switch item.body {
        Option.Some(body) : appendLines(lines, dumpBlock(body, indent + "  ")),
        Option.None : (),
    }
    lines
}

func dumpStruct(StructDecl item) Vec[string] {
    var lines = Vec[string]()
    var prefix = if item.isPublic { "pub " } else { "" }
    lines.push(prefix + "struct " + item.name + fmtGenerics(item.generics))
    var _fi = 0
    while _fi < item.fields.len() {
        var field = item.fields[_fi]
        var fp = if field.isPublic { "pub " } else { "" }
        lines.push("  " + fp + field.typeName + " " + field.name)
        _fi = _fi + 1
    }
    lines
}

func dumpEnum(EnumDecl item) Vec[string] {
    var lines = Vec[string]()
    lines.push("enum " + item.name + fmtGenerics(item.generics))
    var _vi = 0
    while _vi < item.variants.len() {
        var variant = item.variants[_vi]
        switch variant.payload {
            Option.Some(payload) : lines.push("  " + variant.name + "(" + payload + ")"),
            Option.None : lines.push("  " + variant.name),
        }
        _vi = _vi + 1
    }
    lines
}

func dumpTrait(TraitDecl item) Vec[string] {
    var lines = Vec[string]()
    var prefix = if item.isPublic { "pub " } else { "" }
    lines.push(prefix + "trait " + item.name + fmtGenerics(item.generics))
    var _mi = 0
    while _mi < item.methods.len() {
        var method = item.methods[_mi]
        var params = Vec[string]()
        var _mpi = 0
        while _mpi < method.params.len() {
            var param = method.params[_mpi]
            params.push(param.typeName + " " + param.name)
            _mpi = _mpi + 1
        }
        var ret =
            switch method.returnType {
                Option.Some(value) : " -> " + value,
                Option.None : "",
            }
        lines.push(
            "  func "
                + method.name
                + fmtGenerics(method.generics)
                + "("
                + joinWith(params, ", ")
                + ")"
                + ret
        )
    }
    lines
}

func dumpImpl(ImplDecl item) Vec[string] {
    var lines = Vec[string]()
    var head =
        switch item.traitName {
            Option.Some(name) : name + " for " + item.target,
            Option.None : item.target,
        }
    var title = replaceOnce("impl " + fmtGenerics(item.generics) + " " + head, "impl  ", "impl ")
    lines.push(title)
    var _mi2 = 0
    while _mi2 < item.methods.len() {
        var method = item.methods[_mi2]
        appendLines(lines, dumpFunction(method, "  "))
        _mi2 = _mi2 + 1
    }
    lines
}

func dumpBlock(BlockExpr block, string indent) Vec[string] {
    var lines = Vec[string]()
    var _si = 0
    while _si < block.statements.len() {
        var stmt = block.statements[_si]
        appendLines(lines, dumpStmt(stmt, indent))
        _si = _si + 1
    }
    switch block.finalExpr {
        Option.Some(expr) : lines.push(indent + "final " + dumpExpr(expr)),
        Option.None : (),
    }
    lines
}

func dumpStmt(Stmt stmt, string indent) Vec[string] {
    switch stmt {
        Stmt.Var(value) : {
            var text =
                switch value.typeName {
                    Option.Some(typeName) : indent + typeName + " " + value.name + " = " + dumpExpr(value.value),
                    Option.None : indent + "var " + value.name + " = " + dumpExpr(value.value),
            }
            singleLine(text)
        }
        Stmt.Assign(value) : {
            singleLine(indent + value.name + " = " + dumpExpr(value.value))
        }
        Stmt.Increment(value) : {
            singleLine(indent + value.name + "++")
        }
        Stmt.CFor(value) : {
            var lines = Vec[string]()
            lines.push(
                indent
                    + "for ("
                    + dumpForClause(value.init.value)
                    + "; "
                    + dumpExpr(value.condition)
                    + "; "
                    + dumpForClause(value.step.value)
                    + ")"
            )
            appendLines(lines, dumpBlock(value.body, indent + "  "))
            lines
        }
        Stmt.Return(value) : {
            var text =
                switch value.value {
                    Option.Some(expr) : indent + "return " + dumpExpr(expr),
                    Option.None : indent + "return ()",
                }
            singleLine(text)
        }
        Stmt.Expr(value) : singleLine(indent + "expr " + dumpExpr(value.expr)),
        Stmt.Defer(value) : singleLine(indent + "defer " + dumpExpr(value.expr)),
    }
}

func dumpForClause(Stmt stmt) string {
    switch stmt {
        Stmt.Var(value) : {
            switch value.typeName {
                Option.Some(typeName) : typeName + " " + value.name + " = " + dumpExpr(value.value),
                Option.None : "var " + value.name + " = " + dumpExpr(value.value),
            }
        }
        Stmt.Assign(value) : value.name + " = " + dumpExpr(value.value),
        Stmt.Increment(value) : value.name + "++",
        Stmt.Expr(value) : dumpExpr(value.expr),
        Stmt.Return(_) : "return",
        Stmt.CFor(_) : "for (...)",
    }
}

func dumpExpr(Expr expr) string {
    switch expr {
        Expr.Int(value) : value.value,
        Expr.string(value) : value.value,
        Expr.Bool(value) : if value.value { "true" } else { "false" },
        Expr.Name(value) : value.name,
        Expr.Borrow(value) : {
            var prefix = if value.mutable { "&mut " } else { "&" }
            prefix + dumpExpr(value.target.value)
        }
        Expr.Binary(value) : "(" + dumpExpr(value.left.value) + " " + value.op + " " + dumpExpr(value.right.value) + ")",
        Expr.Member(value) : dumpExpr(value.target.value) + "." + value.member,
        Expr.Index(value) : dumpExpr(value.target.value) + "[" + dumpExpr(value.index.value) + "]",
        Expr.Call(value) : "call " + dumpExpr(value.callee.value) + "(" + joinExprs(value.args) + ")",
        Expr.Switch(value) : "switch " + dumpExpr(value.subject.value) + " { " + joinSwitchArms(value.arms) + " }",
        Expr.If(value) : dumpIfExpr(value),
        Expr.While(value) : "while " + dumpExpr(value.condition.value) + " {...}",
        Expr.For(value) : {
            var names = ""
            var i = 0
            while i < value.names.len() {
                if i > 0 {
                    names = names + ", "
                }
                names = names + value.names[i]
                i = i + 1
            }
            var decl = if value.declare { " := " } else { " in " }
            "for " + names + decl + dumpExpr(value.iterable.value) + " {...}"
        }
        Expr.Block(_) : "{...}",
        Expr.Array(value) : {
            var elems = Vec[string]()
            var _ei = 0
            while _ei < value.items.len() { elems.push(dumpExpr(value.items[_ei])); _ei = _ei + 1 }
            "[" + joinWith(elems, ", ") + "]"
        }
        Expr.Map(value) : {
            var parts = Vec[string]()
            var _en = 0
            while _en < value.entries.len() { var entry = value.entries[_en]; parts.push(dumpExpr(entry.key) + ": " + dumpExpr(entry.value)); _en = _en + 1 }
            "{" + joinWith(parts, ", ") + "}"
        }
    }
}

func dumpIfExpr(IfExpr value) string {
    var text = "if " + dumpExpr(value.condition.value) + " {...}"
    switch value.elseBranch {
        Option.Some(expr) : text + " else " + dumpExpr(expr.value),
        Option.None : text,
    }
}

func dumpPattern(Pattern pattern) string {
    switch pattern {
        Pattern.Name(value) : value.name,
        Pattern.Wildcard(_) : "_",
        Pattern.Literal(value) : dumpExpr(value.value),
        Pattern.Variant(value) : {
            if len(value.args) == 0 {
                return value.path
            }
            value.path + "(" + joinPatterns(value.args) + ")"
        }
    }
}

func joinExprs(Vec[Expr] values) string {
    var parts = Vec[string]()
    var _iv = 0
    while _iv < values.len() {
        var value = values[_iv]
        parts.push(dumpExpr(value))
        _iv = _iv + 1
    }
    joinWith(parts, ", ")
}

func joinPatterns(Vec[Pattern] values) string {
    var parts = Vec[string]()
    var _pv = 0
    while _pv < values.len() { parts.push(dumpPattern(values[_pv])); _pv = _pv + 1 }
    joinWith(parts, ", ")
}

func joinSwitchArms(Vec[SwitchArm] values) string {
    var parts = Vec[string]()
    var _mv = 0
    while _mv < values.len() {
        var value = values[_mv]
        parts.push(dumpPattern(value.pattern) + " : " + dumpExpr(value.expr))
        _mv = _mv + 1
    }
    joinWith(parts, "; ")
}

func appendLines(Vec[string] dest, Vec[string] source) () {
    var _li = 0
    while _li < source.len() {
        dest.push(source[_li])
        _li = _li + 1
    }
}

func singleLine(string text) Vec[string] {
    var lines = Vec[string]()
    lines.push(text)
    lines
}

func joinLines(Vec[string] lines) string {
    joinWith(lines, "\n")
}
func joinWith(Vec[string] values, string sep) string {
    var out = ""
    var first = true
    var _j = 0
    while _j < values.len() {
        var value = values[_j]
        if !first {
            out = out + sep
        }
        out = out + value
        first = false
        _j = _j + 1
    }
    out
}

func replaceOnce(string text, string from, string to) string {
    text
}
