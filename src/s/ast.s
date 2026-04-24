package s

use std.option.option
use std.prelude.box
use std.prelude.to_string
use std.vec.vec

struct use_decl {
    string path
    option[string] alias
}

struct field {
    string name
    string type_name
    bool is_public
}

struct param {
    string name
    string type_name
}

struct function_sig {
    string name
    vec[string] generics
    vec[param] params
    option[string] return_type
}

struct name_pattern {
    string name
}

struct wildcard_pattern {}

struct variant_pattern {
    string path
    vec[pattern] args
}

struct literal_pattern {
    expr value
}

enum pattern {
    name(name_pattern),
    wildcard(wildcard_pattern),
    variant(variant_pattern),
    literal(literal_pattern),
}

struct int_expr {
    string value
    option[string] inferred_type
}

struct string_expr {
    string value
    option[string] inferred_type
}

struct bool_expr {
    bool value
    option[string] inferred_type
}

struct name_expr {
    string name
    option[string] inferred_type
}

struct borrow_expr {
    box[expr] target
    bool mutable
    option[string] inferred_type
}

struct binary_expr {
    box[expr] left
    string op
    box[expr] right
    option[string] inferred_type
}

struct member_expr {
    box[expr] target
    string member
    option[string] inferred_type
}

struct index_expr {
    box[expr] target
    box[expr] index
    option[string] inferred_type
}

struct call_expr {
    box[expr] callee
    vec[expr] args
    option[string] inferred_type
}

struct switch_arm {
    pattern pattern
    expr expr
}

struct switch_expr {
    box[expr] subject
    vec[switch_arm] arms
    option[string] inferred_type
}

struct if_expr {
    box[expr] condition
    block_expr then_branch
    option[box[expr]] else_branch
    option[string] inferred_type
}

struct while_expr {
    box[expr] condition
    block_expr body
    option[string] inferred_type
}

struct for_expr {
    vec[string] names
    bool declare
    box[expr] iterable
    block_expr body
    option[string] inferred_type
}

struct block_expr {
    vec[stmt] statements
    option[expr] final_expr
    option[string] inferred_type
}

struct array_literal {
    option[string] type_text
    vec[expr] items
}

struct map_entry {
    expr key
    expr value
}

struct map_literal {
    option[string] type_text
    vec[map_entry] entries
}

enum expr {
    int(int_expr),
    string(string_expr),
    bool(bool_expr),
    name(name_expr),
    borrow(borrow_expr),
    binary(binary_expr),
    member(member_expr),
    index(index_expr),
    call(call_expr),
    switch(switch_expr),
    if(if_expr),
    while(while_expr),
    for(for_expr),
    block(block_expr),
    array(array_literal),
    map(map_literal),
}

struct var_stmt {
    string name
    option[string] type_name
    expr value
}

struct assign_stmt {
    string name
    expr value
}

struct increment_stmt {
    string name
}

struct c_for_stmt {
    box[stmt] init
    expr condition
    box[stmt] step
    block_expr body
}

struct return_stmt {
    option[expr] value
}

struct expr_stmt {
    expr expr
}

struct defer_stmt {
    expr expr
}

struct sroutine_stmt {
    expr expr
}

enum stmt {
    var(var_stmt),
    assign(assign_stmt),
    increment(increment_stmt),
    c_for(c_for_stmt),
    return(return_stmt),
    expr(expr_stmt),
    defer(defer_stmt),
    sroutine(sroutine_stmt),
}

struct function_decl {
    function_sig sig
    option[block_expr] body
    bool is_public
}

struct struct_decl {
    string name
    vec[string] generics
    vec[field] fields
    bool is_public
}

struct enum_variant {
    string name
    option[string] payload
}

struct enum_decl {
    string name
    vec[string] generics
    vec[enum_variant] variants
    bool is_public
}

struct trait_decl {
    string name
    vec[string] generics
    vec[function_sig] methods
    bool is_public
}

struct impl_decl {
    string target
    option[string] trait_name
    vec[string] generics
    vec[function_decl] methods
}

struct const_decl {
    string name
    option[expr] value
    int iota_index
}

enum item {
    function(function_decl),
    const(const_decl),
    struct(struct_decl),
    enum(enum_decl),
    trait(trait_decl),
    impl(impl_decl),
}

struct source_file {
    string pkg
    vec[use_decl] uses
    vec[item] items
}

func dump_source_file(source_file source) string {
    var lines = vec[string]()
    lines.push("package " + source.pkg);
    var ui = 0
    while ui < source.uses.len() {
        var use_decl = source.uses[ui]
        var text =
            switch use_decl.alias {
                option.some(alias) : "use " + use_decl.path + " as " + alias,
                option.none : "use " + use_decl.path,
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

func append_item_dump(vec[string] lines, item item) () {
    switch item {
        item.function(value) : append_lines(lines, dump_function(value, "")),
        item.const(value) : append_lines(lines, dump_const(value)),
        item.struct(value) : append_lines(lines, dump_struct(value)),
        item.enum(value) : append_lines(lines, dump_enum(value)),
        item.trait(value) : append_lines(lines, dump_trait(value)),
        item.impl(value) : append_lines(lines, dump_impl(value)),
    }
}

func dump_const(const_decl item) vec[string] {
    switch item.value {
        option.some(value) : vec[string] { "const " + item.name + " = " + dump_expr(value) },
        option.none : vec[string] { "const " + item.name },
    }
}

func fmt_generics(vec[string] generics) string {
    if len(generics) == 0 {
        return ""
    }
    "[" + join_with(generics, ", ") + "]"
}

func dump_function(function_decl item, string indent) vec[string] {
    var lines = vec[string]()
    var params = vec[string]()
    var _pi = 0
    while _pi < item.sig.params.len() {
        var param = item.sig.params[_pi]
        params.push(param.type_name + " " + param.name)
        _pi = _pi + 1
    }
    var ret =
        switch item.sig.return_type {
            option.some(value) : " -> " + value,
            option.none : "",
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
        option.some(body) : append_lines(lines, dump_block(body, indent + "  ")),
        option.none : (),
    }
    lines
}

func dump_struct(struct_decl item) vec[string] {
    var lines = vec[string]()
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

func dump_enum(enum_decl item) vec[string] {
    var lines = vec[string]()
    lines.push("enum " + item.name + fmt_generics(item.generics))
    var _vi = 0
    while _vi < item.variants.len() {
        var variant = item.variants[_vi]
        switch variant.payload {
            option.some(payload) : lines.push("  " + variant.name + "(" + payload + ")"),
            option.none : lines.push("  " + variant.name),
        }
        _vi = _vi + 1
    }
    lines
}

func dump_trait(trait_decl item) vec[string] {
    var lines = vec[string]()
    var prefix = if item.is_public { "pub " } else { "" }
    lines.push(prefix + "trait " + item.name + fmt_generics(item.generics))
    var _mi = 0
    while _mi < item.methods.len() {
        var method = item.methods[_mi]
        var params = vec[string]()
        var _mpi = 0
        while _mpi < method.params.len() {
            var param = method.params[_mpi]
            params.push(param.type_name + " " + param.name)
            _mpi = _mpi + 1
        }
        var ret =
            switch method.return_type {
                option.some(value) : " -> " + value,
                option.none : "",
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

func dump_impl(impl_decl item) vec[string] {
    var lines = vec[string]()
    var head =
        switch item.trait_name {
            option.some(name) : name + " for " + item.target,
            option.none : item.target,
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

func dump_block(block_expr block, string indent) vec[string] {
    var lines = vec[string]()
    var _si = 0
    while _si < block.statements.len() {
        var stmt = block.statements[_si]
        append_lines(lines, dump_stmt(stmt, indent))
        _si = _si + 1
    }
    switch block.final_expr {
        option.some(expr) : lines.push(indent + "final " + dump_expr(expr)),
        option.none : (),
    }
    lines
}

func dump_stmt(stmt stmt, string indent) vec[string] {
    switch stmt {
        stmt.var(value) : {
            var text =
                switch value.type_name {
                    option.some(type_name) : indent + type_name + " " + value.name + " = " + dump_expr(value.value),
                    option.none : indent + "var " + value.name + " = " + dump_expr(value.value),
            }
            single_line(text)
        }
        stmt.assign(value) : {
            single_line(indent + value.name + " = " + dump_expr(value.value))
        }
        stmt.increment(value) : {
            single_line(indent + value.name + "++")
        }
        stmt.c_for(value) : {
            var lines = vec[string]()
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
        stmt.return(value) : {
            var text =
                switch value.value {
                    option.some(expr) : indent + "return " + dump_expr(expr),
                    option.none : indent + "return ()",
                }
            single_line(text)
        }
        stmt.expr(value) : single_line(indent + "expr " + dump_expr(value.expr)),
        stmt.defer(value) : single_line(indent + "defer " + dump_expr(value.expr)),
        stmt.sroutine(value) : single_line(indent + "sroutine " + dump_expr(value.expr)),
    }
}

func dump_for_clause(stmt stmt) string {
    switch stmt {
        stmt.var(value) : {
            switch value.type_name {
                option.some(type_name) : type_name + " " + value.name + " = " + dump_expr(value.value),
                option.none : "var " + value.name + " = " + dump_expr(value.value),
            }
        }
        stmt.assign(value) : value.name + " = " + dump_expr(value.value),
        stmt.increment(value) : value.name + "++",
        stmt.expr(value) : dump_expr(value.expr),
        stmt.return(_) : "return",
        stmt.c_for(_) : "for (...)",
        stmt.defer(_) : "defer",
        stmt.sroutine(_) : "sroutine",
    }
}

func dump_expr(expr expr) string {
    switch expr {
        expr.int(value) : value.value,
        expr.string(value) : value.value,
        expr.bool(value) : if value.value { "true" } else { "false" },
        expr.name(value) : value.name,
        expr.borrow(value) : {
            var prefix = if value.mutable { "&mut " } else { "&" }
            prefix + dump_expr(value.target.value)
        }
        expr.binary(value) : "(" + dump_expr(value.left.value) + " " + value.op + " " + dump_expr(value.right.value) + ")",
        expr.member(value) : dump_expr(value.target.value) + "." + value.member,
        expr.index(value) : dump_expr(value.target.value) + "[" + dump_expr(value.index.value) + "]",
        expr.call(value) : "call " + dump_expr(value.callee.value) + "(" + join_exprs(value.args) + ")",
        expr.switch(value) : "switch " + dump_expr(value.subject.value) + " { " + join_switch_arms(value.arms) + " }",
        expr.if(value) : dump_if_expr(value),
        expr.while(value) : "while " + dump_expr(value.condition.value) + " {...}",
        expr.for(value) : {
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
        expr.block(_) : "{...}",
        expr.array(value) : {
            var elems = vec[string]()
            var _ei = 0
            while _ei < value.items.len() { elems.push(dump_expr(value.items[_ei])); _ei = _ei + 1 }
            "[" + join_with(elems, ", ") + "]"
        }
        expr.map(value) : {
            var parts = vec[string]()
            var _en = 0
            while _en < value.entries.len() { var entry = value.entries[_en]; parts.push(dump_expr(entry.key) + ": " + dump_expr(entry.value)); _en = _en + 1 }
            "{" + join_with(parts, ", ") + "}"
        }
    }
}

func dump_if_expr(if_expr value) string {
    var text = "if " + dump_expr(value.condition.value) + " {...}"
    switch value.else_branch {
        option.some(expr) : text + " else " + dump_expr(expr.value),
        option.none : text,
    }
}

func dump_pattern(pattern pattern) string {
    switch pattern {
        pattern.name(value) : value.name,
        pattern.wildcard(_) : "_",
        pattern.literal(value) : dump_expr(value.value),
        pattern.variant(value) : {
            if len(value.args) == 0 {
                return value.path
            }
            value.path + "(" + join_patterns(value.args) + ")"
        }
    }
}

func join_exprs(vec[expr] values) string {
    var parts = vec[string]()
    var _iv = 0
    while _iv < values.len() {
        var value = values[_iv]
        parts.push(dump_expr(value))
        _iv = _iv + 1
    }
    join_with(parts, ", ")
}

func join_patterns(vec[pattern] values) string {
    var parts = vec[string]()
    var _pv = 0
    while _pv < values.len() { parts.push(dump_pattern(values[_pv])); _pv = _pv + 1 }
    join_with(parts, ", ")
}

func join_switch_arms(vec[switch_arm] values) string {
    var parts = vec[string]()
    var _mv = 0
    while _mv < values.len() {
        var value = values[_mv]
        parts.push(dump_pattern(value.pattern) + " : " + dump_expr(value.expr))
        _mv = _mv + 1
    }
    join_with(parts, "; ")
}

func append_lines(vec[string] dest, vec[string] source) () {
    var _li = 0
    while _li < source.len() {
        dest.push(source[_li])
        _li = _li + 1
    }
}

func single_line(string text) vec[string] {
    var lines = vec[string]()
    lines.push(text)
    lines
}

func join_lines(vec[string] lines) string {
    join_with(lines, "\n")
}
func join_with(vec[string] values, string sep) string {
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
