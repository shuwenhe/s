package s

use std.option.Option
use std.prelude.box
use std.prelude.to_string
use std.vec.Vec

struct use_decl {
    string path,
    Option[string] alias,
}

struct Field {
    string name,
    string type_name,
    bool is_public,
}

struct Param {
    string name,
    string type_name,
}

struct function_sig {
    string name,
    Vec[string] generics,
    Vec[Param] params,
    Option[string] return_type,
}

struct name_pattern {
    string name,
}

struct wildcard_pattern {}

struct variant_pattern {
    string path,
    Vec[Pattern] args,
}

struct literal_pattern {
    Expr value,
}

enum Pattern {
    Name(name_pattern),
    Wildcard(wildcard_pattern),
    Variant(variant_pattern),
    Literal(literal_pattern),
}

struct int_expr {
    string value,
    Option[string] inferred_type,
}

struct string_expr {
    string value,
    Option[string] inferred_type,
}

struct bool_expr {
    bool value,
    Option[string] inferred_type,
}

struct name_expr {
    string name,
    Option[string] inferred_type,
}

struct borrow_expr {
    Box[Expr] target,
    bool mutable,
    Option[string] inferred_type,
}

struct binary_expr {
    Box[Expr] left,
    string op,
    Box[Expr] right,
    Option[string] inferred_type,
}

struct member_expr {
    Box[Expr] target,
    string member,
    Option[string] inferred_type,
}

struct index_expr {
    Box[Expr] target,
    Box[Expr] index,
    Option[string] inferred_type,
}

struct call_expr {
    Box[Expr] callee,
    Vec[Expr] args,
    Option[string] inferred_type,
}

struct switch_arm {
    Pattern pattern,
    Expr expr,
}

struct switch_expr {
    Box[Expr] subject,
    Vec[switch_arm] arms,
    Option[string] inferred_type,
}

struct if_expr {
    Box[Expr] condition,
    block_expr then_branch,
    Option[Box[Expr]] else_branch,
    Option[string] inferred_type,
}

struct while_expr {
    Box[Expr] condition,
    block_expr body,
    Option[string] inferred_type,
}

struct for_expr {
    Vec[string] names,
    bool declare,
    Box[Expr] iterable,
    block_expr body,
    Option[string] inferred_type,
}

struct block_expr {
    Vec[Stmt] statements,
    Option[Expr] final_expr,
    Option[string] inferred_type,
}

struct array_literal {
    Option[string] type_text,
    Vec[Expr] items,
}

struct map_entry {
    Expr key,
    Expr value,
}

struct map_literal {
    Option[string] type_text,
    Vec[map_entry] entries,
}

enum Expr {
    Int(int_expr),
    string(string_expr),
    Bool(bool_expr),
    Name(name_expr),
    Borrow(borrow_expr),
    Binary(binary_expr),
    Member(member_expr),
    Index(index_expr),
    Call(call_expr),
    Switch(switch_expr),
    If(if_expr),
    While(while_expr),
    For(for_expr),
    Block(block_expr),
    Array(array_literal),
    Map(map_literal),
}

struct var_stmt {
    string name,
    Option[string] type_name,
    Expr value,
}

struct assign_stmt {
    string name,
    Expr value,
}

struct increment_stmt {
    string name,
}

struct c_for_stmt {
    Box[Stmt] init,
    Expr condition,
    Box[Stmt] step,
    block_expr body,
}

struct return_stmt {
    Option[Expr] value,
}

struct expr_stmt {
    Expr expr,
}

struct defer_stmt {
    Expr expr,
}

enum Stmt {
    Var(var_stmt),
    Assign(assign_stmt),
    Increment(increment_stmt),
    c_for(c_for_stmt),
    Return(return_stmt),
    Expr(expr_stmt),
    Defer(defer_stmt),
}

struct function_decl {
    function_sig sig,
    Option[block_expr] body,
    bool is_public,
}

struct struct_decl {
    string name,
    Vec[string] generics,
    Vec[Field] fields,
    bool is_public,
}

struct enum_variant {
    string name,
    Option[string] payload,
}

struct enum_decl {
    string name,
    Vec[string] generics,
    Vec[enum_variant] variants,
    bool is_public,
}

struct trait_decl {
    string name,
    Vec[string] generics,
    Vec[function_sig] methods,
    bool is_public,
}

struct impl_decl {
    string target,
    Option[string] trait_name,
    Vec[string] generics,
    Vec[function_decl] methods,
}

enum Item {
    Function(function_decl),
    Struct(struct_decl),
    Enum(enum_decl),
    Trait(trait_decl),
    Impl(impl_decl),
}

struct source_file {
    string pkg,
    Vec[use_decl] uses,
    Vec[Item] items,
}

func dump_source_file(source_file source) string {
    var lines = Vec[string]()
    lines.push("package " + source.pkg);
    var ui = 0
    while ui < source.uses.len() {
        var use_decl = source.uses[ui]
        var text =
            switch use_decl.alias {
                Option.Some(alias) : "use " + use_decl.path + " as " + alias,
                Option.None : "use " + use_decl.path,
            }
        lines.push(text);
        ui = ui + 1
    }
    var ii = 0
    while ii < source.items.len() {
        var item = source.items[ii]
        append_item_dump(lines, item);
        ii = ii + 1
    }
    join_lines(lines)
}

func append_item_dump(Vec[string] lines, Item item) () {
    switch item {
        Item.Function(value) : append_lines(lines, dump_function(value, "")),
        Item.Struct(value) : append_lines(lines, dump_struct(value)),
        Item.Enum(value) : append_lines(lines, dump_enum(value)),
        Item.Trait(value) : append_lines(lines, dump_trait(value)),
        Item.Impl(value) : append_lines(lines, dump_impl(value)),
    }
}

func fmt_generics(Vec[string] generics) string {
    if len(generics) == 0 {
        return ""
    }
    "[" + join_with(generics, ", ") + "]"
}

func dump_function(function_decl item, string indent) Vec[string] {
    var lines = Vec[string]()
    var params = Vec[string]()
    var _pi = 0
    while _pi < item.sig.params.len() {
        var param = item.sig.params[_pi]
        params.push(param.type_name + " " + param.name)
        _pi = _pi + 1
    }
    var ret =
        switch item.sig.return_type {
            Option.Some(value) : " -> " + value,
            Option.None : "",
        }
    var prefix = if item.is_public { "pub " } else { "" }
    lines.push(
        indent
            + prefix
            + "func "
            + item.sig.name
            + fmt_generics(item.sig.generics)
            + "("
            + join_with(params, ", ")
            + ")"
            + ret
    )
    switch item.body {
        Option.Some(body) : append_lines(lines, dump_block(body, indent + "  ")),
        Option.None : (),
    }
    lines
}

func dump_struct(struct_decl item) Vec[string] {
    var lines = Vec[string]()
    var prefix = if item.is_public { "pub " } else { "" }
    lines.push(prefix + "struct " + item.name + fmt_generics(item.generics))
    var _fi = 0
    while _fi < item.fields.len() {
        var field = item.fields[_fi]
        var fp = if field.is_public { "pub " } else { "" }
        lines.push("  " + fp + field.type_name + " " + field.name)
        _fi = _fi + 1
    }
    lines
}

func dump_enum(enum_decl item) Vec[string] {
    var lines = Vec[string]()
    lines.push("enum " + item.name + fmt_generics(item.generics))
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

func dump_trait(trait_decl item) Vec[string] {
    var lines = Vec[string]()
    var prefix = if item.is_public { "pub " } else { "" }
    lines.push(prefix + "trait " + item.name + fmt_generics(item.generics))
    var _mi = 0
    while _mi < item.methods.len() {
        var method = item.methods[_mi]
        var params = Vec[string]()
        var _mpi = 0
        while _mpi < method.params.len() {
            var param = method.params[_mpi]
            params.push(param.type_name + " " + param.name)
            _mpi = _mpi + 1
        }
        var ret =
            switch method.return_type {
                Option.Some(value) : " -> " + value,
                Option.None : "",
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

func dump_impl(impl_decl item) Vec[string] {
    var lines = Vec[string]()
    var head =
        switch item.trait_name {
            Option.Some(name) : name + " for " + item.target,
            Option.None : item.target,
        }
    var title = replace_once("impl " + fmt_generics(item.generics) + " " + head, "impl  ", "impl ")
    lines.push(title)
    var _mi2 = 0
    while _mi2 < item.methods.len() {
        var method = item.methods[_mi2]
        append_lines(lines, dump_function(method, "  "))
        _mi2 = _mi2 + 1
    }
    lines
}

func dump_block(block_expr block, string indent) Vec[string] {
    var lines = Vec[string]()
    var _si = 0
    while _si < block.statements.len() {
        var stmt = block.statements[_si]
        append_lines(lines, dump_stmt(stmt, indent))
        _si = _si + 1
    }
    switch block.final_expr {
        Option.Some(expr) : lines.push(indent + "final " + dump_expr(expr)),
        Option.None : (),
    }
    lines
}

func dump_stmt(Stmt stmt, string indent) Vec[string] {
    switch stmt {
        Stmt.Var(value) : {
            var text =
                switch value.type_name {
                    Option.Some(type_name) : indent + type_name + " " + value.name + " = " + dump_expr(value.value),
                    Option.None : indent + "var " + value.name + " = " + dump_expr(value.value),
            }
            single_line(text)
        }
        Stmt.Assign(value) : {
            single_line(indent + value.name + " = " + dump_expr(value.value))
        }
        Stmt.Increment(value) : {
            single_line(indent + value.name + "++")
        }
        Stmt.c_for(value) : {
            var lines = Vec[string]()
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
        Stmt.Return(value) : {
            var text =
                switch value.value {
                    Option.Some(expr) : indent + "return " + dump_expr(expr),
                    Option.None : indent + "return ()",
                }
            single_line(text)
        }
        Stmt.Expr(value) : single_line(indent + "expr " + dump_expr(value.expr)),
        Stmt.Defer(value) : single_line(indent + "defer " + dump_expr(value.expr)),
    }
}

func dump_for_clause(Stmt stmt) string {
    switch stmt {
        Stmt.Var(value) : {
            switch value.type_name {
                Option.Some(type_name) : type_name + " " + value.name + " = " + dump_expr(value.value),
                Option.None : "var " + value.name + " = " + dump_expr(value.value),
            }
        }
        Stmt.Assign(value) : value.name + " = " + dump_expr(value.value),
        Stmt.Increment(value) : value.name + "++",
        Stmt.Expr(value) : dump_expr(value.expr),
        Stmt.Return(_) : "return",
        Stmt.c_for(_) : "for (...)",
    }
}

func dump_expr(Expr expr) string {
    switch expr {
        Expr.Int(value) : value.value,
        Expr.string(value) : value.value,
        Expr.Bool(value) : if value.value { "true" } else { "false" },
        Expr.Name(value) : value.name,
        Expr.Borrow(value) : {
            var prefix = if value.mutable { "&mut " } else { "&" }
            prefix + dump_expr(value.target.value)
        }
        Expr.Binary(value) : "(" + dump_expr(value.left.value) + " " + value.op + " " + dump_expr(value.right.value) + ")",
        Expr.Member(value) : dump_expr(value.target.value) + "." + value.member,
        Expr.Index(value) : dump_expr(value.target.value) + "[" + dump_expr(value.index.value) + "]",
        Expr.Call(value) : "call " + dump_expr(value.callee.value) + "(" + join_exprs(value.args) + ")",
        Expr.Switch(value) : "switch " + dump_expr(value.subject.value) + " { " + join_switch_arms(value.arms) + " }",
        Expr.If(value) : dump_if_expr(value),
        Expr.While(value) : "while " + dump_expr(value.condition.value) + " {...}",
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
            "for " + names + decl + dump_expr(value.iterable.value) + " {...}"
        }
        Expr.Block(_) : "{...}",
        Expr.Array(value) : {
            var elems = Vec[string]()
            var _ei = 0
            while _ei < value.items.len() { elems.push(dump_expr(value.items[_ei])); _ei = _ei + 1 }
            "[" + join_with(elems, ", ") + "]"
        }
        Expr.Map(value) : {
            var parts = Vec[string]()
            var _en = 0
            while _en < value.entries.len() { var entry = value.entries[_en]; parts.push(dump_expr(entry.key) + ": " + dump_expr(entry.value)); _en = _en + 1 }
            "{" + join_with(parts, ", ") + "}"
        }
    }
}

func dump_if_expr(if_expr value) string {
    var text = "if " + dump_expr(value.condition.value) + " {...}"
    switch value.else_branch {
        Option.Some(expr) : text + " else " + dump_expr(expr.value),
        Option.None : text,
    }
}

func dump_pattern(Pattern pattern) string {
    switch pattern {
        Pattern.Name(value) : value.name,
        Pattern.Wildcard(_) : "_",
        Pattern.Literal(value) : dump_expr(value.value),
        Pattern.Variant(value) : {
            if len(value.args) == 0 {
                return value.path
            }
            value.path + "(" + join_patterns(value.args) + ")"
        }
    }
}

func join_exprs(Vec[Expr] values) string {
    var parts = Vec[string]()
    var _iv = 0
    while _iv < values.len() {
        var value = values[_iv]
        parts.push(dump_expr(value))
        _iv = _iv + 1
    }
    join_with(parts, ", ")
}

func join_patterns(Vec[Pattern] values) string {
    var parts = Vec[string]()
    var _pv = 0
    while _pv < values.len() { parts.push(dump_pattern(values[_pv])); _pv = _pv + 1 }
    join_with(parts, ", ")
}

func join_switch_arms(Vec[switch_arm] values) string {
    var parts = Vec[string]()
    var _mv = 0
    while _mv < values.len() {
        var value = values[_mv]
        parts.push(dump_pattern(value.pattern) + " : " + dump_expr(value.expr))
        _mv = _mv + 1
    }
    join_with(parts, "; ")
}

func append_lines(Vec[string] dest, Vec[string] source) () {
    var _li = 0
    while _li < source.len() {
        dest.push(source[_li])
        _li = _li + 1
    }
}

func single_line(string text) Vec[string] {
    var lines = Vec[string]()
    lines.push(text)
    lines
}

func join_lines(Vec[string] lines) string {
    join_with(lines, "\n")
}
func join_with(Vec[string] values, string sep) string {
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

func replace_once(string text, string from, string to) string {
    text
}
