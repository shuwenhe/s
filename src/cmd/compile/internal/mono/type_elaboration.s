package compile.internal.mono
import ("compile.internal.ast"; "compile.internal.typesys"; "std.option"; "std.prelude")

// A concrete type is keyed by its declaration index and its canonical arguments.
// Packages stay parallel to items throughout elaboration.
struct type_elaboration_result { source_file file; string error }
struct te_request { string type_name; string pkg }
struct te_alias { string pkg; string original; string concrete }
struct te_instance { int declaration; string original; string concrete; string pkg; string[] args }
struct te_type_result { string text; te_request[] requests; string error }

func te_no_expr() option[expr] { option.none }
func te_rewrite_type(string text, string[] keys, string[] values) string {
    clean := compile.internal.typesys.parse_type(text)
    i := 0
    for i < len(keys) { if clean == keys[i] { return values[i] }
 i = i + 1 }
    if te_starts_with(clean, "*") { return "*" + te_rewrite_type(prelude_slice(clean, 1, len(clean)), keys, values) }
    if te_ends_with(clean, "*") { return te_rewrite_type(prelude_slice(clean, 0, len(clean)-1), keys, values) + "*" }
    if te_ends_with(clean, "[]") { return te_rewrite_type(prelude_slice(clean, 0, len(clean)-2), keys, values) + "[]" }
    if te_starts_with(clean, "&mut") { return "&mut " + te_rewrite_type(prelude_slice(clean, 4, len(clean)), keys, values) }
    if te_starts_with(clean, "&") { return "&" + te_rewrite_type(prelude_slice(clean, 1, len(clean)), keys, values) }
    if te_starts_with(clean, "[]") { return "[]" + te_rewrite_type(prelude_slice(clean, 2, len(clean)), keys, values) }
    wrapper := te_array_wrapper(clean)
    if wrapper != "" { return te_rewrite_type(prelude_slice(clean, 0, len(clean)-len(wrapper)), keys, values) + wrapper }
    if te_starts_with(clean, "[") {
        close := find_char(clean, "]")
        if close > 0 { return prelude_slice(clean, 0, close+1) + te_rewrite_type(prelude_slice(clean, close+1, len(clean)), keys, values) }
    }
    if compile.internal.typesys.is_tuple_type(clean) {
        tuple_args := compile.internal.typesys.extract_tuple_args(clean); tuple_text := "("; ti := 0
        for ti < len(tuple_args) { if ti > 0 { tuple_text = tuple_text + "," }
 tuple_text = tuple_text + te_rewrite_type(tuple_args[ti], keys, values); ti = ti + 1 }
        return tuple_text + ")"
    }
    args := compile.internal.typesys.extract_type_args(clean)
    if len(args) == 0 { return clean }
    out := te_rewrite_type(compile.internal.typesys.base_type_name(clean), keys, values) + "["
    i = 0
    for i < len(args) { if i > 0 { out = out + "," }
 out = out + te_rewrite_type(args[i], keys, values); i = i + 1 }
    return out + "]"
}
func te_rewrite_optional_type(option[string] value, string[] keys, string[] values) option[string] {
    switch value { option.some(text): option.some(te_rewrite_type(text, keys, values)), option.none: option.none }
}
func te_rewrite_exprs(expr[] initial_items, string[] keys, string[] values) expr[] {
    items := initial_items
    i := 0
    for i < len(items) { items[i] = te_rewrite_expr(items[i], keys, values); i = i + 1 }
    items
}
func te_rewrite_pattern(pattern value, string[] keys, string[] values) pattern {
    switch value {
        pattern.variant(v): { v.path = te_rewrite_path(v.path, keys, values); i := 0; for i < len(v.args) { v.args[i] = te_rewrite_pattern(v.args[i], keys, values); i = i + 1 }
 pattern.variant(v) },
        pattern.literal(v): pattern.literal(literal_pattern { value: te_rewrite_expr(v.value, keys, values) }),
        _: value,
    }
}
func te_rewrite_block(block_expr block, string[] generic_names, string[] type_args) block_expr {
    stmts := stmt[]()
    i := 0
    for i < len(block.statements) {
        stmts = append(stmts, te_rewrite_stmt(block.statements[i], generic_names, type_args))
        i = i + 1
    }
    final_expr := te_no_expr()
    switch block.final_expr {
        option.some(value) : final_expr = option.some(te_rewrite_expr(value, generic_names, type_args)),
        option.none : (),
    }
    block_expr { statements: stmts, final_expr: final_expr, inferred_type: te_rewrite_optional_type(block.inferred_type, generic_names, type_args) }
}

func te_rewrite_stmt(stmt value, string[] generic_names, string[] type_args) stmt {
    switch value {
        stmt.continue(_) : value,
        stmt.break(_) : value,
        stmt.let(v) : stmt.let(var_stmt { name: v.name, type_name te_rewrite_optional_type(v.type_name, generic_names, type_args), value te_rewrite_expr(v.value, generic_names, type_args) }),
        stmt.assign(v) : stmt.assign(compile.internal.ast.assign_stmt { name: v.name, value te_rewrite_expr(v.value, generic_names, type_args) }),
        stmt.store(v) : { v.target = te_rewrite_expr(v.target, generic_names, type_args); v.value = te_rewrite_expr(v.value, generic_names, type_args); stmt.store(v) },
        stmt.multi(v) : { v.targets = te_rewrite_exprs(v.targets, generic_names, type_args); v.value = te_rewrite_expr(v.value, generic_names, type_args); stmt.multi(v) },
        stmt.increment(v) : stmt.increment(compile.internal.ast.increment_stmt { name: v.name }),
        stmt.c_for(v) : stmt.c_for(c_for_stmt { init: std.prelude.box(te_rewrite_stmt(v.init.value, generic_names, type_args)), condition te_rewrite_expr(v.condition, generic_names, type_args), step std.prelude.box(te_rewrite_stmt(v.step.value, generic_names, type_args)), body te_rewrite_block(v.body, generic_names, type_args) }),
        stmt.return(v) : {
            ret := te_no_expr()
            switch v.value {
                option.some(e) : ret = option.some(te_rewrite_expr(e, generic_names, type_args)),
                option.none : (),
            }
            stmt.return(compile.internal.ast.return_stmt { value: ret })
        }
        stmt.expr(v) : stmt.expr(compile.internal.ast.expr_stmt { expr: te_rewrite_expr(v.expr, generic_names, type_args) }),
        stmt.defer(v) : stmt.defer(defer_stmt { expr: te_rewrite_expr(v.expr, generic_names, type_args) }),
        stmt.sroutine(v) : stmt.sroutine(sroutine_stmt { expr: te_rewrite_expr(v.expr, generic_names, type_args) }),
    }
}

func te_rewrite_expr(expr value, string[] generic_names, string[] type_args) expr {
    switch value {
        expr.int(v) : { v.inferred_type = te_rewrite_optional_type(v.inferred_type, generic_names, type_args); expr.int(v) },
        expr.string(v) : { v.inferred_type = te_rewrite_optional_type(v.inferred_type, generic_names, type_args); expr.string(v) },
        expr.bool(v) : { v.inferred_type = te_rewrite_optional_type(v.inferred_type, generic_names, type_args); expr.bool(v) },
        expr.name(v) : { v.name = te_rewrite_path(v.name, generic_names, type_args); v.inferred_type = te_rewrite_optional_type(v.inferred_type, generic_names, type_args); expr.name(v) },
        expr.record(v) : { v.type_name = te_rewrite_type(v.type_name, generic_names, type_args); v.field_values = te_rewrite_exprs(v.field_values, generic_names, type_args); v.inferred_type = te_rewrite_optional_type(v.inferred_type, generic_names, type_args); expr.record(v) },
        expr.tuple(v) : { v.items = te_rewrite_exprs(v.items, generic_names, type_args); v.inferred_type = te_rewrite_optional_type(v.inferred_type, generic_names, type_args); expr.tuple(v) },
        expr.borrow(v) : expr.borrow(compile.internal.ast.borrow_expr { target: std.prelude.box(te_rewrite_expr(v.target.value, generic_names, type_args)), mutable v.mutable, inferred_type te_rewrite_optional_type(v.inferred_type, generic_names, type_args) }),
        expr.binary(v) : expr.binary(compile.internal.ast.binary_expr { left: std.prelude.box(te_rewrite_expr(v.left.value, generic_names, type_args)), op v.op, right std.prelude.box(te_rewrite_expr(v.right.value, generic_names, type_args)), inferred_type te_rewrite_optional_type(v.inferred_type, generic_names, type_args) }),
        expr.member(v) : expr.member(compile.internal.ast.member_expr { target: std.prelude.box(te_rewrite_expr(v.target.value, generic_names, type_args)), member v.member, inferred_type te_rewrite_optional_type(v.inferred_type, generic_names, type_args) }),
        expr.index(v) : expr.index(compile.internal.ast.index_expr { target: std.prelude.box(te_rewrite_expr(v.target.value, generic_names, type_args)), index std.prelude.box(te_rewrite_expr(v.index.value, generic_names, type_args)), inferred_type te_rewrite_optional_type(v.inferred_type, generic_names, type_args) }),
        expr.call(v) : {
            args := expr[]()
            i := 0
            for i < len(v.args) {
                args = append(args, te_rewrite_expr(v.args[i], generic_names, type_args))
                i = i + 1
            }
            call_type_args := string[]()
            i = 0
            for i < len(v.type_args) {
                call_type_args = append(call_type_args, te_rewrite_type(v.type_args[i], generic_names, type_args))
                i = i + 1
            }
            resolved := v.resolved_callee
            switch resolved { option.some(path): resolved = option.some(te_rewrite_path(path, generic_names, type_args)), option.none: () }
            expr.call(compile.internal.ast.call_expr { callee: std.prelude.box(te_rewrite_expr(v.callee.value, generic_names, type_args)), args args, inferred_type te_rewrite_optional_type(v.inferred_type, generic_names, type_args), resolved_callee resolved, type_args call_type_args })
        }
        expr.if(v) : {
            else_branch := te_no_box_expr()
            switch v.else_branch {
                option.some(e) : else_branch = option.some(std.prelude.box(te_rewrite_expr(e.value, generic_names, type_args))),
                option.none : (),
            }
            expr.if(if_expr { condition: std.prelude.box(te_rewrite_expr(v.condition.value, generic_names, type_args)), then_branch te_rewrite_block(v.then_branch, generic_names, type_args), else_branch else_branch, inferred_type te_rewrite_optional_type(v.inferred_type, generic_names, type_args) })
        }
        expr.for(v) : te_rewrite_for_expr(v, generic_names, type_args),
        expr.while(v) : expr.while(while_expr { condition: std.prelude.box(te_rewrite_expr(v.condition.value, generic_names, type_args)), body te_rewrite_block(v.body, generic_names, type_args), inferred_type te_rewrite_optional_type(v.inferred_type, generic_names, type_args) }),
        expr.block(v) : expr.block(te_rewrite_block(v, generic_names, type_args)),
        expr.switch(v) : expr.switch(te_rewrite_switch(v, generic_names, type_args)),
        expr.array(v) : te_rewrite_array_expr(v, generic_names, type_args),
        expr.map(v) : te_rewrite_map_expr(v, generic_names, type_args),
    }
}

func te_rewrite_for_expr(for_expr v, string[] generic_names, string[] type_args) expr {
    init := te_no_box_stmt()
    switch v.init {
        option.some(s) : init = option.some(std.prelude.box(te_rewrite_stmt(s.value, generic_names, type_args))),
        option.none : (),
    }
    condition := te_no_box_expr()
    switch v.condition {
        option.some(e) : condition = option.some(std.prelude.box(te_rewrite_expr(e.value, generic_names, type_args))),
        option.none : (),
    }
    post := te_no_box_stmt()
    switch v.post {
        option.some(s) : post = option.some(std.prelude.box(te_rewrite_stmt(s.value, generic_names, type_args))),
        option.none : (),
    }
    iterable := te_no_box_expr()
    switch v.iterable {
        option.some(e) : iterable = option.some(std.prelude.box(te_rewrite_expr(e.value, generic_names, type_args))),
        option.none : (),
    }
    expr.for(for_expr { init: init, condition: condition, post: post, names: v.names, iterable: iterable, body: te_rewrite_block(v.body, generic_names, type_args), inferred_type: te_rewrite_optional_type(v.inferred_type, generic_names, type_args) })
}

func te_rewrite_switch(switch_expr v, string[] generic_names, string[] type_args) switch_expr {
    arms := switch_arm[]()
    i := 0
    for i < len(v.arms) {
        arms = append(arms, switch_arm { pattern: te_rewrite_pattern(v.arms[i].pattern, generic_names, type_args), expr te_rewrite_expr(v.arms[i].expr, generic_names, type_args) })
        i = i + 1
    }
    switch_expr { subject: std.prelude.box(te_rewrite_expr(v.subject.value, generic_names, type_args)), arms arms, inferred_type te_rewrite_optional_type(v.inferred_type, generic_names, type_args) }
}

func te_rewrite_array_expr(array_literal v, string[] generic_names, string[] type_args) expr {
    items := expr[]()
    i := 0
    for i < len(v.items) {
        items = append(items, te_rewrite_expr(v.items[i], generic_names, type_args))
        i = i + 1
    }
    expr.array(array_literal { type_text: te_rewrite_optional_type(v.type_text, generic_names, type_args), items items })
}

func te_rewrite_map_expr(map_literal v, string[] generic_names, string[] type_args) expr {
    entries := map_entry[]()
    i := 0
    for i < len(v.entries) {
        entries = append(entries, map_entry { key: te_rewrite_expr(v.entries[i].key, generic_names, type_args), value te_rewrite_expr(v.entries[i].value, generic_names, type_args) })
        i = i + 1
    }
    expr.map(map_literal { type_text: te_rewrite_optional_type(v.type_text, generic_names, type_args), entries entries })
}
func te_add_optional(string[] initial_out, option[string] value) string[] {
    out := initial_out
    switch value { option.some(t): out = append(out, t), option.none: () }
    out
}
func te_join(string[] initial_out, string[] more) string[] {
    out := initial_out
    i := 0; for i < len(more) { out = append(out, more[i]); i = i + 1 }
 out
}
func te_expr_types(expr value) string[] {
    out := string[]()
    switch value {
        expr.int(v): out = te_add_optional(out, v.inferred_type),
        expr.string(v): out = te_add_optional(out, v.inferred_type),
        expr.bool(v): out = te_add_optional(out, v.inferred_type),
        expr.name(v): out = te_add_optional(out, v.inferred_type),
        expr.record(v): { out = append(out, v.type_name); out = te_add_optional(out, v.inferred_type); out = te_join(out, te_exprs_types(v.field_values)) },
        expr.tuple(v): { out = te_add_optional(out, v.inferred_type); out = te_join(out, te_exprs_types(v.items)) },
        expr.borrow(v): { out = te_add_optional(out, v.inferred_type); out = te_join(out, te_expr_types(v.target.value)) },
        expr.binary(v): { out = te_add_optional(out, v.inferred_type); out = te_join(out, te_expr_types(v.left.value)); out = te_join(out, te_expr_types(v.right.value)) },
        expr.member(v): { out = te_add_optional(out, v.inferred_type); out = te_join(out, te_expr_types(v.target.value)) },
        expr.index(v): { out = te_add_optional(out, v.inferred_type); out = te_join(out, te_expr_types(v.target.value)); out = te_join(out, te_expr_types(v.index.value)) },
        expr.call(v): { out = te_add_optional(out, v.inferred_type); out = te_join(out, v.type_args); out = te_join(out, te_expr_types(v.callee.value)); out = te_join(out, te_exprs_types(v.args)) },
        expr.if(v): { out = te_add_optional(out, v.inferred_type); out = te_join(out, te_expr_types(v.condition.value)); out = te_join(out, te_block_types(v.then_branch)); switch v.else_branch { option.some(e): out = te_join(out, te_expr_types(e.value)), option.none: () } },
        expr.while(v): { out = te_add_optional(out, v.inferred_type); out = te_join(out, te_expr_types(v.condition.value)); out = te_join(out, te_block_types(v.body)) },
        expr.for(v): {
            out = te_add_optional(out, v.inferred_type); out = te_join(out, te_block_types(v.body))
            switch v.init { option.some(s): out = te_join(out, te_stmt_types(s.value)), option.none: () }
            switch v.post { option.some(s): out = te_join(out, te_stmt_types(s.value)), option.none: () }
            switch v.condition { option.some(e): out = te_join(out, te_expr_types(e.value)), option.none: () }
            switch v.iterable { option.some(e): out = te_join(out, te_expr_types(e.value)), option.none: () }
        },
        expr.block(v): out = te_join(out, te_block_types(v)),
        expr.switch(v): { out = te_add_optional(out, v.inferred_type); out = te_join(out, te_expr_types(v.subject.value)); i := 0; for i < len(v.arms) { out = te_join(out, te_expr_types(v.arms[i].expr)); out = te_join(out, te_pattern_types(v.arms[i].pattern)); i = i + 1 } },
        expr.array(v): { out = te_add_optional(out, v.type_text); out = te_join(out, te_exprs_types(v.items)) },
        expr.map(v): { out = te_add_optional(out, v.type_text); i := 0; for i < len(v.entries) { out = te_join(out, te_expr_types(v.entries[i].key)); out = te_join(out, te_expr_types(v.entries[i].value)); i = i + 1 } },
    }
    out
}
func te_pattern_types(pattern value) string[] {
    out := string[]()
    switch value {
        pattern.variant(v): { i := 0; for i < len(v.args) { out = te_join(out, te_pattern_types(v.args[i])); i = i + 1 } },
        pattern.literal(v): out = te_expr_types(v.value),
        _: (),
    }
    out
}
func te_exprs_types(expr[] values) string[] {
    out := string[](); i := 0; for i < len(values) { out = te_join(out, te_expr_types(values[i])); i = i + 1 }
 out
}
func te_stmt_types(stmt value) string[] {
    out := string[]()
    switch value {
        stmt.continue(_) : (),
        stmt.break(_) : (),
        stmt.let(v): { out = te_add_optional(out, v.type_name); out = te_join(out, te_expr_types(v.value)) },
        stmt.assign(v): out = te_expr_types(v.value),
        stmt.store(v): { out = te_expr_types(v.target); out = te_join(out, te_expr_types(v.value)) },
        stmt.multi(v): { out = te_exprs_types(v.targets); out = te_join(out, te_expr_types(v.value)) },
        stmt.increment(v): (),
        stmt.return(v): { switch v.value { option.some(e): out = te_expr_types(e), option.none: () } },
        stmt.expr(v): out = te_expr_types(v.expr),
        stmt.defer(v): out = te_expr_types(v.expr),
        stmt.sroutine(v): out = te_expr_types(v.expr),
        stmt.c_for(v): { out = te_stmt_types(v.init.value); out = te_join(out, te_stmt_types(v.step.value)); out = te_join(out, te_expr_types(v.condition)); out = te_join(out, te_block_types(v.body)) },
    }
    out
}
func te_block_types(block_expr value) string[] {
    out := te_add_optional(string[](), value.inferred_type)
    i := 0; for i < len(value.statements) { out = te_join(out, te_stmt_types(value.statements[i])); i = i + 1 }
    switch value.final_expr { option.some(e): out = te_join(out, te_expr_types(e)), option.none: () }
 out
}
func te_function_types(function_decl value) string[] {
    out := te_add_optional(string[](), value.sig.return_type)
    i := 0; for i < len(value.sig.params) { out = append(out, value.sig.params[i].type_name); i = i + 1 }
    switch value.body { option.some(b): out = te_join(out, te_block_types(b)), option.none: () }
 out
}
func te_item_types(item value) string[] {
    out := string[]()
    switch value {
        item.function(v): out = te_function_types(v),
        item.method(v): { out = append(out, v.receiver_type); out = te_join(out, te_function_types(v.method)) },
        item.struct(v): { i := 0; for i < len(v.fields) { out = append(out, v.fields[i].type_name); i = i + 1 } },
        item.enum(v): { i := 0; for i < len(v.variants) { out = te_add_optional(out, v.variants[i].payload); i = i + 1 } },
        item.var(v): { out = te_add_optional(out, v.type_name); switch v.value { option.some(e): out = te_join(out, te_expr_types(e)), option.none: () } },
        item.const(v): { switch v.value { option.some(e): out = te_expr_types(e), option.none: () } },
        item.trait(v): (),
    }
 out
}
func te_rewrite_function(function_decl initial_value, string[] keys, string[] values) function_decl {
    value := initial_value
    i := 0; for i < len(value.sig.params) { value.sig.params[i].type_name = te_rewrite_type(value.sig.params[i].type_name, keys, values); i = i + 1 }
    value.sig.return_type = te_rewrite_optional_type(value.sig.return_type, keys, values)
    switch value.body { option.some(b): value.body = option.some(te_rewrite_block(b, keys, values)), option.none: () }
 value
}
func te_rewrite_item(item value, string[] keys, string[] values) item {
    switch value {
        item.function(v): item.function(te_rewrite_function(v, keys, values)),
        item.method(v): { v.receiver_type = te_rewrite_type(v.receiver_type, keys, values); v.method = te_rewrite_function(v.method, keys, values); item.method(v) },
        item.struct(v): { i := 0; for i < len(v.fields) { v.fields[i].type_name = te_rewrite_type(v.fields[i].type_name, keys, values); i = i + 1 }
 item.struct(v) },
        item.enum(v): { i := 0; for i < len(v.variants) { v.variants[i].payload = te_rewrite_optional_type(v.variants[i].payload, keys, values); i = i + 1 }
 item.enum(v) },
        item.var(v): { v.type_name = te_rewrite_optional_type(v.type_name, keys, values); switch v.value { option.some(e): v.value = option.some(te_rewrite_expr(e, keys, values)), option.none: () }
 item.var(v) },
        item.const(v): { switch v.value { option.some(e): v.value = option.some(te_rewrite_expr(e, keys, values)), option.none: () }
 item.const(v) },
        item.trait(v): item.trait(v),
    }
}
func te_package(source_file file, int index) string {
    if index < len(file.item_packages) { return file.item_packages[index] }
 file.pkg
}
func te_generics(item value) string[] {
    switch value { item.struct(v): v.generics, item.enum(v): v.generics, item.function(v): v.sig.generics, item.method(v): v.method.sig.generics, item.trait(v): v.generics, _: string[]() }
}
func te_decl_name(item value) string {
    switch value { item.struct(v): v.name, item.enum(v): v.name, _: "" }
}
func te_add_requests(te_request[] initial_requests, string[] names, string pkg) te_request[] {
    requests := initial_requests
    i := 0; for i < len(names) { requests = append(requests, te_request { type_name: names[i], pkg: pkg }); i = i + 1 }
 requests
}
// Expand only reachable concrete declarations. A work item is registered before
// visiting its fields, so recursive records terminate without dropping fields.
func elaborate_generic_types(source_file file) type_elaboration_result {
    output := source_file { pkg: file.pkg, uses: file.uses, items: item[](), item_packages: string[]() }
    requests := te_request[]()
    instances := te_instance[]()
    aliases := te_alias[]()
    i := 0
    for i < len(file.items) {
        value := file.items[i]
        if len(te_generics(value)) == 0 || te_decl_name(value) == "" {
            output.items = append(output.items, value)
            output.item_packages = append(output.item_packages, te_package(file, i))
            if len(te_generics(value)) == 0 { requests = te_add_requests(requests, te_item_types(value), te_package(file, i)) }
        }
        i = i + 1
    }
    cursor := 0
    for cursor < len(requests) {
        if cursor > 100000 { return type_elaboration_result { file: output, error: "generic type expansion does not terminate" } }
        request := requests[cursor]; cursor = cursor + 1
        text := compile.internal.typesys.parse_type(request.type_name)
        if te_starts_with(text, "*") { requests = append(requests, te_request { type_name: prelude_slice(text, 1, len(text)), pkg: request.pkg }); continue }
        if te_ends_with(text, "*") { requests = append(requests, te_request { type_name: prelude_slice(text, 0, len(text)-1), pkg: request.pkg }); continue }
        if te_starts_with(text, "&mut") { requests = append(requests, te_request { type_name: prelude_slice(text, 4, len(text)), pkg: request.pkg }); continue }
        if te_starts_with(text, "&") { requests = append(requests, te_request { type_name: prelude_slice(text, 1, len(text)), pkg: request.pkg }); continue }
        if te_ends_with(text, "[]") { requests = append(requests, te_request { type_name: prelude_slice(text, 0, len(text)-2), pkg: request.pkg }); continue }
        if te_starts_with(text, "[]") { requests = append(requests, te_request { type_name: prelude_slice(text, 2, len(text)), pkg: request.pkg }); continue }
        wrapper := te_array_wrapper(text)
        if wrapper != "" { requests = append(requests, te_request { type_name: prelude_slice(text, 0, len(text)-len(wrapper)), pkg: request.pkg }); continue }
        if te_starts_with(text, "[") {
            close := find_char(text, "]")
            if close > 0 { requests = append(requests, te_request { type_name: prelude_slice(text, close+1, len(text)), pkg: request.pkg }); continue }
        }
        if compile.internal.typesys.is_tuple_type(text) { requests = te_add_requests(requests, compile.internal.typesys.extract_tuple_args(text), request.pkg); continue }
        args := compile.internal.typesys.extract_type_args(text)
        base := compile.internal.typesys.base_type_name(text)
        declaration := te_find_declaration(file, base, request.pkg)
        if declaration == -2 { return type_elaboration_result { file: output, error: "ambiguous type declaration: " + text + " in " + request.pkg } }
        if declaration < 0 {
            if len(args) > 0 { return type_elaboration_result { file: output, error: "generic type declaration not found: " + text + " in " + request.pkg } }
            continue
        }
        generics := generic_names_from_sig(te_generics(file.items[declaration]))
        if len(generics) != len(args) { return type_elaboration_result { file: output, error: "generic type arity mismatch: " + text } }
        if len(args) == 0 { continue }
        pkg := te_package(file, declaration)
        if pkg != request.pkg {
            qi := 0
            for qi < len(args) { args[qi] = te_qualify_type(file, args[qi], request.pkg); qi = qi + 1 }
        }
        name := te_decl_name(file.items[declaration])
        concrete := make_instance_name(name, args)
        target := pkg + "." + concrete
        if pkg == request.pkg { target = concrete }
        aliases = append(aliases, te_alias { pkg: request.pkg, original: text, concrete: target })
        qualified_original := pkg + "." + name + prelude_slice(text, len(base), len(text))
        aliases = append(aliases, te_alias { pkg: "", original: qualified_original, concrete: pkg + "." + concrete })
        seen := false; i = 0
        for i < len(instances) { if instances[i].declaration == declaration && same_type_args(instances[i].args, args) { seen = true }
 i = i + 1 }
        if seen { continue }
        i = 0
        for i < len(instances) {
            if instances[i].pkg == pkg && instances[i].concrete == concrete { return type_elaboration_result { file: output, error: "generic type instance name collision: " + pkg + "." + concrete } }
            i = i + 1
        }
        i = 0
        for i < len(file.items) {
            if te_package(file, i) == pkg && te_decl_name(file.items[i]) == concrete { return type_elaboration_result { file: output, error: "generic type instance conflicts with declaration: " + pkg + "." + concrete } }
            i = i + 1
        }
        instances = append(instances, te_instance { declaration: declaration, original: text, concrete: concrete, pkg: pkg, args: args })
        value := te_rewrite_item(file.items[declaration], generics, args)
        switch value {
            item.struct(v): { v.name = concrete; v.generics = string[](); value = item.struct(v) },
            item.enum(v): { v.name = concrete; v.generics = string[](); value = item.enum(v) },
            _: return type_elaboration_result { file: output, error: "generic type is not a record or enum: " + text },
        }
        output.items = append(output.items, value); output.item_packages = append(output.item_packages, pkg)
        requests = te_add_requests(requests, args, request.pkg)
        requests = te_add_requests(requests, te_item_types(value), pkg)
    }
    i = 0
    for i < len(output.items) {
        keys := string[](); values := string[](); j := 0
        for j < len(aliases) {
            alias := aliases[j]
            if alias.pkg == "" || output.item_packages[i] == alias.pkg { keys = append(keys, alias.original); values = append(values, alias.concrete) }
            j = j + 1
        }
        output.items[i] = te_rewrite_item(output.items[i], keys, values)
        i = i + 1
    }
    type_elaboration_result { file: output, error: "" }
}

func te_starts_with(string text, string prefix) bool { if len(text) < len(prefix) { return false }
 prelude_slice(text, 0, len(prefix)) == prefix }
func te_ends_with(string text, string suffix) bool { if len(text) < len(suffix) { return false }
 prelude_slice(text, len(text)-len(suffix), len(text)) == suffix }

func te_no_box_expr() option[box[expr]] { option.none }
func te_no_box_stmt() option[box[stmt]] { option.none }

// Numeric suffix dimensions are arrays rather than generic applications.
func te_array_wrapper(string text) string {
    if !te_ends_with(text, "]") { return "" }
    i := len(text)-2
    for i >= 0 {
        ch := string(text[i])
        if ch == "[" { if i == len(text)-2 { return "" }
 return prelude_slice(text, i, len(text)) }
        if ch != "0" && ch != "1" && ch != "2" && ch != "3" && ch != "4" && ch != "5" && ch != "6" && ch != "7" && ch != "8" && ch != "9" { return "" }
        i = i - 1
    }
    ""
}
func te_rewrite_path(string text, string[] keys, string[] values) string {
    i := 0
    for i < len(keys) { if text == keys[i] { return values[i] }
 if te_starts_with(text, keys[i] + ".") { return values[i] + prelude_slice(text, len(keys[i]), len(text)) }
 i = i + 1 }
    text
}

// Prefer the containing package, then explicit qualification, then imported
// declarations. An ambiguous import is an error, never first/last-match wins.
func te_find_declaration(source_file file, string base, string pkg) int {
    i := 0
    for i < len(file.items) {
        name := te_decl_name(file.items[i]); owner := te_package(file, i)
        if name != "" && (base == owner + "." + name || (base == name && owner == pkg)) { return i }
        i = i + 1
    }
    found := -1; i = 0
    for i < len(file.items) {
        name := te_decl_name(file.items[i]); owner := te_package(file, i)
        if name != "" {
            imported := owner == "std.prelude" && (base == name || base == "prelude." + name); ui := 0
            for ui < len(file.uses) {
                import_decl := file.uses[ui]
                if import_decl.path == owner {
                    if base == name { imported = true }
                    switch import_decl.alias { option.some(alias): { if base == alias + "." + name { imported = true } }, option.none: () }
                    short := ""; pi := 0
                    for pi < len(owner) { ch := string(owner[pi]); if ch == "." { short = "" } else { short = short + ch }
 pi = pi + 1 }
                    if base == short + "." + name { imported = true }
                }
                ui = ui + 1
            }
            if imported {
                if found >= 0 { return -2 }
                found = i
            }
        }
        i = i + 1
    }
    found
}
func te_qualify_type(source_file file, string text, string pkg) string {
    keys := string[](); values := string[](); i := 0
    for i < len(file.items) {
        name := te_decl_name(file.items[i])
        if name != "" && te_find_declaration(file, name, pkg) == i { keys = append(keys, name); values = append(values, te_package(file, i) + "." + name) }
        i = i + 1
    }
    te_rewrite_type(text, keys, values)
}
