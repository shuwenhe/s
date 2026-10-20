package compile.internal.ast
import (
    "std"
    "std.option"
    "std.prelude"
)
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
    string[] generics
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
    value expr
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
    option[string] resolved_callee
    string[] type_args
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
    then_branch block_expr
    option[box[expr]] else_branch
    option[string] inferred_type
}

struct for_expr {
    option[box[stmt]] init
    option[box[expr]] condition
    option[box[stmt]] post
    string[] names
    option[box[expr]] iterable
    body block_expr
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
    key expr
    value expr
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
    value expr
}

struct assign_stmt {
    string name
    value expr
}

struct increment_stmt {
    string name
}

struct c_for_stmt {
    box[stmt] init
    condition expr
    box[stmt] step
    body block_expr
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
    sig function_sig
    option[block_expr] body
    bool is_public
}

struct struct_decl {
    string name
    string[] generics
    field[] fields
    bool is_public
}

struct enum_variant {
    string name
    option[string] payload
    i64 explicit_value
    bool has_explicit_value
}

struct enum_decl {
    string name
    string[] generics
    enum_variant[] variants
    bool is_public
}

struct trait_decl {
    string name
    string[] generics
    function_sig[] methods
    bool is_public
}

struct receiver_method_decl {
    string receiver_name
    string receiver_type
    method function_decl
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
    string[] item_packages
}

func dump_source_file(source_file source) string {
    lines := string[]()
    lines = append(lines, "package " + source.pkg);
    ui := 0
    for ui < len(source.uses) {
        use_decl := source.uses[ui]
        text := "use " + use_decl.path
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

func append_item_dump(string[] lines, item item) () {
}

func dump_const(const_decl item) string[] {
    string[]()
}

func dump_var(var_decl item) string[] {
    string[]()
}

func fmt_generics(string[] generics) string {
    if len(generics) == 0 {
        return ""
    }
    "[" + join_with(generics, ", ") + "]"
}

func dump_function(function_decl item, string indent) string[] {
    string[]()
}

func dump_struct(struct_decl item) string[] {
    lines := string[]()
    prefix := if item.is_public { "pub " } else { "" }
    lines = append(lines, prefix + "struct " + item.name + fmt_generics(item.generics))
    _fi := 0
    for _fi < len(item.fields) {
        field := item.fields[_fi]
        fp := if field.is_public { "pub " } else { "" }
        lines = append(lines, "  " + fp + field.kindname + " " + field.name)
        _fi = _fi + 1
    }
    lines
}

func dump_enum(enum_decl item) string[] {
    string[]()
}

func dump_trait(trait_decl item) string[] {
    string[]()
}
func dump_receiver_method(receiver_method_decl item) string[] {
    string[]()
}

func dump_block(block_expr block, string indent) string[] {
    string[]()
}

func dump_stmt(stmt stmt, string indent) string[] {
    string[]()
}

func dump_for_clause(stmt stmt) string {
    ""
}

func dump_expr(expr expr) string {
    return ""
    /* switch expr {
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
            elems := string[]()
            _ei := 0
            for _ei < len(value.items) { elems = append(elems, dump_expr(value.items[_ei])); _ei = _ei + 1 }
            "[" + join_with(elems, ", ") + "]"
        }
        expr.map(value) : {
            parts := string[]()
            _en := 0
            for _en < len(value.entries) { entry := value.entries[_en]; parts = append(parts, dump_expr(entry.key) + ": " + dump_expr(entry.value)); _en = _en + 1 }
            "{" + join_with(parts, ", ") + "}"
        }
    } */
}

func dump_if_expr(if_expr value) string {
    ""
}

func dump_pattern(pattern pattern) string {
    ""
}

func join_exprs(expr[] values) string {
    parts := string[]()
    _iv := 0
    for _iv < len(values) {
        value := values[_iv]
        parts = append(parts, dump_expr(value))
        _iv = _iv + 1
    }
    join_with(parts, ", ")
}

func join_patterns(pattern[] values) string {
    parts := string[]()
    _pv := 0
    for _pv < len(values) { parts = append(parts, dump_pattern(values[_pv])); _pv = _pv + 1 }
    join_with(parts, ", ")
}

func join_switch_arms(switch_arm[] values) string {
    parts := string[]()
    _mv := 0
    for _mv < len(values) {
        value := values[_mv]
        parts = append(parts, dump_pattern(value.pattern) + " : " + dump_expr(value.expr))
        _mv = _mv + 1
    }
    join_with(parts, "; ")
}

func append_lines_at(string[] dest, string[] source, int index) string[] {
	if index >= len(source) {
		return dest
	}
	append_lines_at(append(dest, source[index]), source, index + 1)
}

func append_lines(string[] dest, string[] source) string[] {
	append_lines_at(dest, source, 0)
}

func single_line(string text) string[] {
    lines := string[]()
    lines = append(lines, text)
    lines
}

func join_lines(string[] lines) string {
    join_with(lines, "\n")
}

func join_with(string[] values, string sep) string {
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
