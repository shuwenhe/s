package s
use std.option.option
use std.prelude.box
use std.prelude.to_string
use std.slices
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
    []string generics
    param[] params
    option[string] return_type
}

struct name_pattern {
    string name
}

struct wildcard_pattern {}

struct variant_pattern {
    string path
    pattern[] args
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
    expr[] args
    option[string] inferred_type
}

struct switch_arm {
    pattern pattern
    expr expr
}

struct switch_expr {
    box[expr] subject
    switch_arm[] arms
    option[string] inferred_type
}

struct if_expr {
    box[expr] condition
    block_expr then_branch
    option[box[expr]] else_branch
    option[string] inferred_type
}

struct for_expr {
    option[box[stmt]] init
    option[box[expr]] condition
    option[box[stmt]] post
    []string names
    option[box[expr]] iterable
    block_expr body
    option[string] inferred_type
}

struct block_expr {
    stmt[] statements
    option[expr] final_expr
    option[string] inferred_type
}

struct array_literal {
    option[string] type_text
    expr[] items
}

struct map_entry {
    expr key
    expr value
}

struct map_literal {
    option[string] type_text
    map_entry[] entries
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
    let(var_stmt),
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
    []string generics
    field[] fields
    bool is_public
}

struct enum_variant {
    string name
    option[string] payload
}

struct enum_decl {
    string name
    []string generics
    enum_variant[] variants
    bool is_public
}

struct trait_decl {
    string name
    []string generics
    function_sig[] methods
    bool is_public
}

struct receiver_method_decl {
    string receiver_name
    string receiver_type
    function_decl method
}

struct const_decl {
    string name
    option[expr] value
    int iota_index
}

struct var_decl {
    string name
    option[string] type_name
    option[expr] value
}
enum item {
    function(function_decl),
    const(const_decl),
    var(var_decl),
    struct(struct_decl),
    enum(enum_decl),
    trait(trait_decl),
    method(receiver_method_decl),
}

struct source_file {
    string pkg
    use_decl[] uses
    item[] items
}

func dump_source_file(source_file source) string {
    lines := []string()
    lines = append(lines, "package " + source.pkg);
    ui := 0
    for ui < len(source.uses) {
        use_decl := source.uses[ui]
        text :=
            switch use_decl.alias {
                option.some(alias) : "use " + use_decl.path + " as " + alias,
                option.none : "use " + use_decl.path,
            }
        lines = append(lines, text);
        ui = ui + 1
    }
    ii := 0
    for ii < len(source.items) {
        item := source.items[ii]
        append_item_dump(lines, item);
        ii = ii + 1
    }
    join_lines(lines)
}

func append_item_dump([]string lines, item item) () {
    switch item {
        item.function(value) : append_lines(lines, dump_function(value, "")),
        item.const(value) : append_lines(lines, dump_const(value)),
        item.var(value) : append_lines(lines, dump_var(value)),
        item.struct(value) : append_lines(lines, dump_struct(value)),
        item.enum(value) : append_lines(lines, dump_enum(value)),
        item.trait(value) : append_lines(lines, dump_trait(value)),
        item.method(value) : append_lines(lines, dump_receiver_method(value)),
    }
}

func dump_const(const_decl item) []string {
    switch item.value {
        option.some(value) : []string { "const " + item.name + " = " + dump_expr(value) },
        option.none : []string { "const " + item.name },
    }
}

func dump_var(var_decl item) []string {
    decl := "var " + item.name
    switch item.type_name {
        option.some(t) : decl = decl + " " + t,
        option.none : {},
    }
    switch item.value {
        option.some(v) : []string { decl + " = " + dump_expr(v) },
        option.none : []string { decl },
    }
}

func fmt_generics([]string generics) string {
    if len(generics) == 0 {
        return ""
    }
    "[" + join_with(generics, ", ") + "]"
}

func dump_function(function_decl item, string indent) []string {
    lines := []string()
    params := []string()
    _pi := 0
    for _pi < len(item.sig.params) {
        param := item.sig.params[_pi]
        params = append(params, param.type_name + " " + param.name)
        _pi = _pi + 1
    }
    ret :=
        switch item.sig.return_type {
            option.some(value) : " -> " + value,
            option.none : "",
        }
    prefix := if item.is_public { "pub " } else { "" }
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

func dump_struct(struct_decl item) []string {
    lines := []string()
    prefix := if item.is_public { "pub " } else { "" }
    lines = append(lines, prefix + "struct " + item.name + fmt_generics(item.generics))
    _fi := 0
    for _fi < len(item.fields) {
        field := item.fields[_fi]
        fp := if field.is_public { "pub " } else { "" }
        lines = append(lines, "  " + fp + field.type_name + " " + field.name)
        _fi = _fi + 1
    }
    lines
}

func dump_enum(enum_decl item) []string {
    lines := []string()
    lines = append(lines, "enum " + item.name + fmt_generics(item.generics))
    _vi := 0
    for _vi < len(item.variants) {
        variant := item.variants[_vi]
        switch variant.payload {
            option.some(payload) : lines = append(lines, "  " + variant.name + "(" + payload + ")"),
            option.none : lines = append(lines, "  " + variant.name),
        }
        _vi = _vi + 1
    }
    lines
}

func dump_trait(trait_decl item) []string {
    lines := []string()
    prefix := if item.is_public { "pub " } else { "" }
    lines = append(lines, prefix + "trait " + item.name + fmt_generics(item.generics))
    _mi := 0
    for _mi < len(item.methods) {
        method := item.methods[_mi]
        params := []string()
        _mpi := 0
        for _mpi < len(method.params) {
            param := method.params[_mpi]
            params = append(params, param.type_name + " " + param.name)
            _mpi = _mpi + 1
        }
        ret :=
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

func dump_receiver_method(receiver_method_decl item) []string {
    lines := []string()
    method := item.method
    params := []string()
    _mi2 := 0
    for _mi2 < len(method.sig.params) {
        param := method.sig.params[_mi2]
        params = append(params, param.type_name + " " + param.name)
        _mi2 = _mi2 + 1
    }
    ret :=
        switch method.sig.return_type {
            option.some(value) : " -> " + value,
            option.none : "",
        }
    lines.push(
        "method ("
            + item.receiver_type
            + " "
            + item.receiver_name
            + ") "
            + method.sig.name
            + fmt_generics(method.sig.generics)
            + "("
            + join_with(params, ", ")
            + ")"
            + ret
    )
    switch method.body {
        option.some(body) : append_lines(lines, dump_block(body, "  ")),
        option.none : (),
    }
    lines
}

func dump_block(block_expr block, string indent) []string {
    lines := []string()
    _si := 0
    for _si < len(block.statements) {
        stmt := block.statements[_si]
        append_lines(lines, dump_stmt(stmt, indent))
        _si = _si + 1
    }
    switch block.final_expr {
        option.some(expr) : lines = append(lines, indent + "final " + dump_expr(expr)),
        option.none : (),
    }
    lines
}

func dump_stmt(stmt stmt, string indent) []string {
    switch stmt {
        stmt.let(value) : {
            text :=
                switch value.type_name {
                    option.some(type_name) : indent + type_name + " " + value.name + " = " + dump_expr(value.value),
                    option.none : indent + "" + value.name + " := " + dump_expr(value.value),
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
            lines := []string()
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
            text :=
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
        stmt.let(value) : {
            switch value.type_name {
                option.some(type_name) : type_name + " " + value.name + " = " + dump_expr(value.value),
                option.none : "" + value.name + " := " + dump_expr(value.value),
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
            prefix := if value.mutable { "&" } else { "&" }
            prefix + dump_expr(value.target.value)
        }
        expr.binary(value) : "(" + dump_expr(value.left.value) + " " + value.op + " " + dump_expr(value.right.value) + ")",
        expr.member(value) : dump_expr(value.target.value) + "." + value.member,
        expr.index(value) : dump_expr(value.target.value) + "[" + dump_expr(value.index.value) + "]",
        expr.call(value) : "call " + dump_expr(value.callee.value) + "(" + join_exprs(value.args) + ")",
        expr.switch(value) : "switch " + dump_expr(value.subject.value) + " { " + join_switch_arms(value.arms) + " }",
        expr.if(value) : dump_if_expr(value),
        expr.for(value) : {
            names := ""
            i := 0
            for i < len(value.names) {
                if i > 0 {
                    names = names + ", "
                }
                names = names + value.names[i]
                i = i + 1
            }
            decl := if value.declare { " := " } else { " in " }
            "for " + names + decl + dump_expr(value.iterable.value) + " {...}"
        }
        expr.block(_) : "{...}",
        expr.array(value) : {
            elems := []string()
            _ei := 0
            for _ei < len(value.items) { elems = append(elems, dump_expr(value.items[_ei])); _ei = _ei + 1 }
            "[" + join_with(elems, ", ") + "]"
        }
        expr.map(value) : {
            parts := []string()
            _en := 0
            for _en < len(value.entries) { entry := value.entries[_en]; parts = append(parts, dump_expr(entry.key) + ": " + dump_expr(entry.value)); _en = _en + 1 }
            "{" + join_with(parts, ", ") + "}"
        }
    }
}

func dump_if_expr(if_expr value) string {
    text := "if " + dump_expr(value.condition.value) + " {...}"
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

func join_exprs(expr[] values) string {
    parts := []string()
    _iv := 0
    for _iv < len(values) {
        value := values[_iv]
        parts = append(parts, dump_expr(value))
        _iv = _iv + 1
    }
    join_with(parts, ", ")
}

func join_patterns(pattern[] values) string {
    parts := []string()
    _pv := 0
    for _pv < len(values) { parts = append(parts, dump_pattern(values[_pv])); _pv = _pv + 1 }
    join_with(parts, ", ")
}

func join_switch_arms(switch_arm[] values) string {
    parts := []string()
    _mv := 0
    for _mv < len(values) {
        value := values[_mv]
        parts = append(parts, dump_pattern(value.pattern) + " : " + dump_expr(value.expr))
        _mv = _mv + 1
    }
    join_with(parts, "; ")
}

func append_lines([]string dest, []string source) () {
    _li := 0
    for _li < len(source) {
        dest = append(dest, source[_li])
        _li = _li + 1
    }
}

func single_line(string text) []string {
    lines := []string()
    lines = append(lines, text)
    lines
}

func join_lines([]string lines) string {
    join_with(lines, "\n")
}

func join_with([]string values, string sep) string {
    out := ""
    first := true
    _j := 0
    for _j < len(values) {
        value := values[_j]
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
