package compile.internal.mono
import ("compile.internal.ast"; "compile.internal.semantic"; "compile.internal.typesys"; "std.option"; "std.prelude")

// Checking validates the program; this pass records the same resolver decisions
// on an explicitly reconstructed AST. No local checker mutation is relied on.
struct canonical_annotation_result { source_file file; string error }
struct ca_context {
    compile.internal.semantic.function_binding[] functions
    compile.internal.semantic.trait_binding[] traits
    compile.internal.semantic.declaration_ref[] declarations
    compile.internal.semantic.type_binding[] env
    string source
    string expected
    string pkg
    string[] generic_names
    int local_start
    bool discard_result
    int loop_depth
}
struct ca_expr_result { compile.internal.ast.expr value; string type_name; string error }
struct ca_block_result { compile.internal.ast.block_expr value; string error }
struct ca_stmt_result { compile.internal.ast.stmt value; compile.internal.semantic.type_binding[] env; string error }

func ca_infer(compile.internal.ast.expr value, ca_context ctx) compile.internal.semantic.check_result {
    scope := compile.internal.semantic.semantic_scope { package_path: ctx.pkg, generic_names: ctx.generic_names, local_start: ctx.local_start, discard_result: ctx.discard_result, loop_depth: ctx.loop_depth }
    compile.internal.semantic.infer_expr_in_scope(value, ctx.env, compile.internal.semantic.borrow_state_new(), ctx.expected, ctx.functions, ctx.traits, ctx.source, compile.internal.semantic.semantic_error[](), ctx.declarations, scope)
}
func ca_bad(compile.internal.ast.expr value, string error) ca_expr_result { ca_expr_result { value: value, type_name: "unknown", error: error } }
func ca_child(compile.internal.ast.expr value, ca_context ctx, string expected) ca_expr_result {
    child := ctx; child.expected = expected; ca_expr(value, child)
}
func ca_block(compile.internal.ast.block_expr original, ca_context context) ca_block_result {
    block := original; ctx := context; ctx.local_start = len(context.env); ctx.env = compile.internal.semantic.clone_env(context.env)
    i := 0
    for i < len(block.statements) {
        statement := ca_stmt(block.statements[i], ctx)
        if statement.error != "" { return ca_block_result { value: block, error: statement.error } }
        block.statements[i] = statement.value; ctx.env = statement.env; i = i + 1
    }
    switch block.final_expr {
        option.some(value): {
            result := ca_expr(value, ctx)
            if result.error != "" { return ca_block_result { value: block, error: result.error } }
            block.final_expr = option.some(result.value); block.inferred_type = option.some(result.type_name)
        },
        option.none: (),
    }
    ca_block_result { value: block, error: "" }
}
func ca_stmt(compile.internal.ast.stmt original, ca_context ctx) ca_stmt_result {
    value := original
    switch value {
        stmt.continue(_): (),
        stmt.break(_): (),
        stmt.let(v): {
            expected := ctx.expected
            switch v.type_name { option.some(t): expected = t, option.none: () }
            child := ca_child(v.value, ctx, expected)
            if child.error != "" { return ca_stmt_result { value: value, env: ctx.env, error: child.error } }
            v.value = child.value; value = stmt.let(v)
        },
        stmt.assign(v): {
            child := ca_child(v.value, ctx, compile.internal.semantic.lookup_name_type(ctx.env, v.name))
            if child.error != "" { return ca_stmt_result { value: value, env: ctx.env, error: child.error } }
            v.value = child.value; value = stmt.assign(v)
        },
        stmt.store(v): {
            target := ca_expr(v.target, ctx)
            if target.error != "" { return ca_stmt_result { value: value, env: ctx.env, error: target.error } }
            child := ca_child(v.value, ctx, target.type_name)
            if child.error != "" { return ca_stmt_result { value: value, env: ctx.env, error: child.error } }
            v.target = target.value; v.value = child.value; value = stmt.store(v)
        },
        stmt.multi(v): {
            child := ca_expr(v.value, ctx)
            if child.error != "" { return ca_stmt_result { value: value, env: ctx.env, error: child.error } }
            v.value = child.value
            // Declaration targets do not yet exist in the lexical environment.
            if !v.declaration { i := 0; for i < len(v.targets) { target := ca_expr(v.targets[i], ctx); if target.error != "" { return ca_stmt_result { value: value, env: ctx.env, error: target.error } }
 v.targets[i] = target.value; i = i + 1 } }
            value = stmt.multi(v)
        },
        stmt.return(v): {
            switch v.value { option.some(e): { child := ca_expr(e, ctx); if child.error != "" { return ca_stmt_result { value: value, env: ctx.env, error: child.error } }
 v.value = option.some(child.value) }, option.none: () }
            value = stmt.return(v)
        },
        stmt.expr(v): { discarded := ctx; discarded.discard_result = true; child := ca_expr(v.expr, discarded); if child.error != "" { return ca_stmt_result { value: value, env: ctx.env, error: child.error } }
 v.expr = child.value; value = stmt.expr(v) },
        stmt.defer(v): { child := ca_expr(v.expr, ctx); if child.error != "" { return ca_stmt_result { value: value, env: ctx.env, error: child.error } }
 v.expr = child.value; value = stmt.defer(v) },
        stmt.sroutine(v): { child := ca_expr(v.expr, ctx); if child.error != "" { return ca_stmt_result { value: value, env: ctx.env, error: child.error } }
 v.expr = child.value; value = stmt.sroutine(v) },
        stmt.increment(v): (),
        stmt.c_for(v): {
            loop := ctx
            init := ca_stmt(v.init.value, loop)
            if init.error != "" { return ca_stmt_result { value: value, env: ctx.env, error: init.error } }
            loop.env = init.env
            condition := ca_child(v.condition, loop, "bool")
            if condition.error != "" { return ca_stmt_result { value: value, env: ctx.env, error: condition.error } }
            step := ca_stmt(v.step.value, loop)
            if step.error != "" { return ca_stmt_result { value: value, env: ctx.env, error: step.error } }
            body_ctx := loop; body_ctx.loop_depth = body_ctx.loop_depth + 1
            body := ca_block(v.body, body_ctx)
            if body.error != "" { return ca_stmt_result { value: value, env: ctx.env, error: body.error } }
            v.init = std.prelude.box(init.value); v.condition = condition.value; v.step = std.prelude.box(step.value); v.body = body.value; value = stmt.c_for(v)
        },
    }
    scope := compile.internal.semantic.semantic_scope { package_path: ctx.pkg, generic_names: ctx.generic_names, local_start: ctx.local_start, discard_result: ctx.discard_result, loop_depth: ctx.loop_depth }
    checked := compile.internal.semantic.check_stmt_with_env_in_scope(original, ctx.env, compile.internal.semantic.borrow_state_new(), ctx.expected, ctx.functions, ctx.traits, ctx.source, compile.internal.semantic.semantic_error[](), ctx.declarations, scope)
    if checked.errors != 0 { return ca_stmt_result { value: value, env: ctx.env, error: "semantic environment reconstruction failed" } }
    ca_stmt_result { value: value, env: checked.env, error: "" }
}
func ca_expr(compile.internal.ast.expr original, ca_context ctx) ca_expr_result {
    inferred := ca_infer(original, ctx)
    if inferred.errors != 0 { return ca_bad(original, "semantic type reconstruction failed in " + ctx.pkg) }
    ctx.discard_result = false
    value := original
    ty := inferred.type_name
    switch value {
        expr.int(v): { v.inferred_type = option.some(ty); value = expr.int(v) },
        expr.string(v): { v.inferred_type = option.some(ty); value = expr.string(v) },
        expr.bool(v): { v.inferred_type = option.some(ty); value = expr.bool(v) },
        expr.name(v): { v.inferred_type = option.some(ty); value = expr.name(v) },
        expr.borrow(v): {
            child := ca_expr(v.target.value, ctx); if child.error != "" { return child }
            v.target = std.prelude.box(child.value); v.inferred_type = option.some(ty); value = expr.borrow(v)
        },
        expr.binary(v): {
            left := ca_expr(v.left.value, ctx); if left.error != "" { return left }
            right := ca_expr(v.right.value, ctx); if right.error != "" { return right }
            v.left = std.prelude.box(left.value); v.right = std.prelude.box(right.value); v.inferred_type = option.some(ty); value = expr.binary(v)
        },
        expr.member(v): {
            path := compile.internal.semantic.qualified_expr_path(original)
            owner := compile.internal.semantic.qualified_package_part(path)
            root_type := compile.internal.semantic.lookup_name_type(ctx.env, compile.internal.semantic.extract_module_root(path))
            if (compile.internal.semantic.is_unknown(root_type) || root_type == "module") && compile.internal.semantic.canonical_enum_index(owner, ctx.declarations) >= 0 {
                // Generic nullary variants acquire their contextual nominal type.
                v.target = std.prelude.box(expr.name(name_expr { name: ty, inferred_type: option.some(ty) }))
            } else {
                child := ca_expr(v.target.value, ctx); if child.error != "" { return child }
                v.target = std.prelude.box(child.value)
            }
            v.inferred_type = option.some(ty); value = expr.member(v)
        },
        expr.index(v): {
            target := ca_expr(v.target.value, ctx); if target.error != "" { return target }
            index := ca_child(v.index.value, ctx, "int"); if index.error != "" { return index }
            v.target = std.prelude.box(target.value); v.index = std.prelude.box(index.value); v.inferred_type = option.some(ty); value = expr.index(v)
        },
        expr.call(v): return ca_call(v, inferred, ctx),
        expr.record(v): {
            i := 0
            for i < len(v.field_values) {
                expected := compile.internal.semantic.canonical_record_field_type(v.type_name, v.field_names[i], ctx.declarations)
                if expected == "" { expected = ctx.expected }
                child := ca_child(v.field_values[i], ctx, expected); if child.error != "" { return child }
                v.field_values[i] = child.value; i = i + 1
            }
            v.inferred_type = option.some(ty); value = expr.record(v)
        },
        expr.tuple(v): {
            types := compile.internal.typesys.extract_tuple_args(ctx.expected); i := 0
            for i < len(v.items) {
                expected := ctx.expected; if i < len(types) { expected = types[i] }
                child := ca_child(v.items[i], ctx, expected); if child.error != "" { return child }
                v.items[i] = child.value; i = i + 1
            }
            v.inferred_type = option.some(ty); value = expr.tuple(v)
        },
        expr.array(v): {
            expected := compile.internal.semantic.canonical_array_element(ty); i := 0
            for i < len(v.items) { child := ca_child(v.items[i], ctx, expected); if child.error != "" { return child }
 v.items[i] = child.value; i = i + 1 }
            value = expr.array(v)
        },
        expr.map(v): {
            i := 0
            for i < len(v.entries) {
                key := ca_expr(v.entries[i].key, ctx); if key.error != "" { return key }
                entry := ca_expr(v.entries[i].value, ctx); if entry.error != "" { return entry }
                v.entries[i].key = key.value; v.entries[i].value = entry.value; i = i + 1
            }
            value = expr.map(v)
        },
        expr.if(v): {
            condition := ca_child(v.condition.value, ctx, "bool"); if condition.error != "" { return condition }
            body := ca_block(v.then_branch, ctx); if body.error != "" { return ca_bad(value, body.error) }
            v.condition = std.prelude.box(condition.value); v.then_branch = body.value
            switch v.else_branch { option.some(e): { child := ca_expr(e.value, ctx); if child.error != "" { return child }
 v.else_branch = option.some(std.prelude.box(child.value)) }, option.none: () }
            v.inferred_type = option.some(ty); value = expr.if(v)
        },
        expr.while(v): {
            condition := ca_child(v.condition.value, ctx, "bool"); if condition.error != "" { return condition }
            body_ctx := ctx; body_ctx.loop_depth = body_ctx.loop_depth + 1
            body := ca_block(v.body, body_ctx); if body.error != "" { return ca_bad(value, body.error) }
            v.condition = std.prelude.box(condition.value); v.body = body.value; v.inferred_type = option.some(ty); value = expr.while(v)
        },
        expr.for(v): {
            loop := ctx; loop.env = compile.internal.semantic.clone_env(ctx.env)
            switch v.init { option.some(s): { init := ca_stmt(s.value, loop); if init.error != "" { return ca_bad(value, init.error) }
 v.init = option.some(std.prelude.box(init.value)); loop.env = init.env }, option.none: () }
            switch v.condition { option.some(e): { child := ca_child(e.value, loop, "bool"); if child.error != "" { return child }
 v.condition = option.some(std.prelude.box(child.value)) }, option.none: () }
            switch v.iterable { option.some(e): { child := ca_expr(e.value, loop); if child.error != "" { return child }
 v.iterable = option.some(std.prelude.box(child.value)) }, option.none: () }
            switch v.post { option.some(s): { post := ca_stmt(s.value, loop); if post.error != "" { return ca_bad(value, post.error) }
 v.post = option.some(std.prelude.box(post.value)) }, option.none: () }
            body_ctx := loop; body_ctx.loop_depth = body_ctx.loop_depth + 1
            body := ca_block(v.body, body_ctx); if body.error != "" { return ca_bad(value, body.error) }
            v.body = body.value; v.inferred_type = option.some(ty); value = expr.for(v)
        },
        expr.block(v): { body := ca_block(v, ctx); if body.error != "" { return ca_bad(value, body.error) }
 value = expr.block(body.value) },
        expr.switch(v): {
            subject := ca_expr(v.subject.value, ctx); if subject.error != "" { return subject }
            v.subject = std.prelude.box(subject.value); i := 0
            for i < len(v.arms) {
                arm := v.arms[i]; arm.pattern = compile.internal.semantic.canonical_resolve_const_pattern(arm.pattern, ctx.env)
                bindings := compile.internal.semantic.pattern_check_result { bindings: compile.internal.semantic.type_binding[](), errors: 0 }
                if compile.internal.semantic.canonical_enum_index(subject.type_name, ctx.declarations) >= 0 { bindings = compile.internal.semantic.canonical_check_enum_pattern(arm.pattern, subject.type_name, ctx.source, compile.internal.semantic.semantic_error[](), ctx.declarations) }
                else { bindings = compile.internal.semantic.check_pattern(arm.pattern, subject.type_name, ctx.source, compile.internal.semantic.semantic_error[]()) }
                if bindings.errors != 0 { return ca_bad(value, "semantic pattern reconstruction failed") }
                arm.pattern = ca_enum_pattern(arm.pattern, subject.type_name, ctx.declarations)
                branch := ctx; branch.env = compile.internal.semantic.clone_env(ctx.env); b := 0
                for b < len(bindings.bindings) { branch.env = append(branch.env, bindings.bindings[b]); b = b + 1 }
                child := ca_expr(arm.expr, branch); if child.error != "" { return child }
                arm.expr = child.value; v.arms[i] = arm; i = i + 1
            }
            v.inferred_type = option.some(ty); value = expr.switch(v)
        },
    }
    ca_expr_result { value: value, type_name: ty, error: "" }
}
// Preserve the subject's concrete enum identity for type elaboration, including
// nested payload patterns whose generic arguments differ from the outer enum.
func ca_enum_pattern(pattern original, string expected, compile.internal.semantic.declaration_ref[] declarations) pattern {
    value := original
    index := compile.internal.semantic.canonical_enum_index(expected, declarations)
    if index < 0 { return value }
    switch value {
        pattern.variant(v): {
            declaration := declarations[index]
            variant := compile.internal.semantic.canonical_enum_variant_index(declaration, compile.internal.semantic.qualified_decl_part(v.path))
            if variant < 0 { return value }
            v.path = expected + "." + declaration.variants[variant].name
            if len(v.args) == 1 {
                payload := compile.internal.semantic.canonical_enum_payload(expected, declaration, variant, declarations)
                v.args[0] = ca_enum_pattern(v.args[0], payload, declarations)
            }
            return pattern.variant(v)
        }
        _: return value,
    }
}

func ca_call(compile.internal.ast.call_expr original, compile.internal.semantic.check_result inferred, ca_context ctx) ca_expr_result {
    ty := inferred.type_name
    new_args := compile.internal.ast.expr[](); arg_types := string[](); i := 0
    for i < len(original.args) {
        argument := ca_expr(original.args[i], ctx)
        if argument.error != "" { return argument }
        new_args = append(new_args, argument.value); arg_types = append(arg_types, argument.type_name); i = i + 1
    }
    resolved := original.resolved_callee
    type_args := original.type_args
    if inferred.resolved_callee != "" {
        resolved = option.some(inferred.resolved_callee)
        type_args = inferred.type_args
    }
    callee := original.callee.value
    path := compile.internal.semantic.qualified_expr_path(callee)
    root_type := compile.internal.semantic.lookup_name_type(ctx.env, compile.internal.semantic.extract_module_root(path))
    if (compile.internal.semantic.is_unknown(root_type) || root_type == "module") && compile.internal.semantic.canonical_enum_index(compile.internal.semantic.qualified_package_part(path), ctx.declarations) >= 0 {
        callee = expr.member(compile.internal.ast.member_expr { target: std.prelude.box(expr.name(name_expr { name: ty, inferred_type: option.some(ty) })), member: compile.internal.semantic.qualified_decl_part(path), inferred_type: option.some(ty) })
    }
    final_call := compile.internal.ast.call_expr { callee: std.prelude.box(callee), args: new_args, inferred_type: option.some(ty), resolved_callee: resolved, type_args: type_args }
    ca_expr_result { value: expr.call(final_call), type_name: ty, error: "" }
}
func annotate_canonical_calls(source_file original, compile.internal.semantic.semantic_result checked, string source) canonical_annotation_result {
    file := original
    ctx := ca_context { functions: checked.functions, traits: compile.internal.semantic.collect_traits(file), declarations: checked.declarations, env: compile.internal.semantic.type_binding[](), source: source, expected: "()", pkg: file.pkg }
    roots := compile.internal.semantic.collect_import_module_roots(file.uses)
    i := 0
    for i < len(roots) { ctx.env = append(ctx.env, compile.internal.semantic.type_binding { name: roots[i], type_name: "module" }); i = i + 1 }
    i = 0
    for i < len(checked.bindings) {
        binding := checked.bindings[i]
        entry := compile.internal.semantic.type_binding { name: binding.name, type_name: binding.type_name, constant: !binding.mutable, constant_value: compile.internal.semantic.canonical_const_pattern_value(binding) }
        ctx.env = append(ctx.env, entry)
        if !te_starts_with(binding.name, binding.package_path + ".") { entry.name = binding.package_path + "." + binding.name; ctx.env = append(ctx.env, entry) }
        i = i + 1
    }
    i = 0
    for i < len(file.items) {
        local := ctx; local.pkg = te_package(file, i); local.env = compile.internal.semantic.clone_env(ctx.env)
        value := file.items[i]
        switch value {
            item.function(f): {
                local = ca_function_context(f, local)
                switch f.body { option.some(b): { body := ca_block(b, local); if body.error != "" { return canonical_annotation_result { file: file, error: body.error + " in " + local.pkg + "." + f.sig.name } }
 f.body = option.some(body.value) }, option.none: () }
                value = item.function(f)
            },
            item.method(m): {
                local.env = append(local.env, compile.internal.semantic.type_binding { name: m.receiver_name, type_name: compile.internal.semantic.canonical_enum_type(compile.internal.typesys.parse_type(m.receiver_type), ctx.declarations) })
                local = ca_function_context(m.method, local)
                switch m.method.body { option.some(b): { body := ca_block(b, local); if body.error != "" { return canonical_annotation_result { file: file, error: body.error + " in receiver method " + m.method.sig.name } }
 m.method.body = option.some(body.value) }, option.none: () }
                value = item.method(m)
            },
            item.var(v): {
                switch v.type_name { option.some(t): local.expected = t, option.none: () }
                switch v.value { option.some(e): { child := ca_expr(e, local); if child.error != "" { return canonical_annotation_result { file: file, error: child.error + " in global " + v.name } }
 v.value = option.some(child.value); if v.type_name.is_none() { v.type_name = option.some(child.type_name) } }, option.none: () }
                value = item.var(v)
            },
            item.const(v): {
                local.env = append(local.env, compile.internal.semantic.type_binding { name: "iota", type_name: "int" })
                switch v.value { option.some(e): { child := ca_expr(e, local); if child.error != "" { return canonical_annotation_result { file: file, error: child.error + " in constant " + v.name } }
 v.value = option.some(child.value) }, option.none: () }
                value = item.const(v)
            },
            _: (),
        }
        file.items[i] = value; i = i + 1
    }
    canonical_annotation_result { file: file, error: "" }
}
func ca_function_context(compile.internal.ast.function_decl function, ca_context initial) ca_context {
    ctx := initial; ctx.expected = "()"
    ctx.generic_names = function.sig.generics
    switch function.sig.return_type { option.some(t): ctx.expected = compile.internal.semantic.canonical_type_in_package(t, ctx.pkg, ctx.generic_names, ctx.declarations), option.none: () }
    i := 0
    for i < len(function.sig.params) {
        parameter := function.sig.params[i]
        ctx.env = append(ctx.env, compile.internal.semantic.type_binding { name: parameter.name, type_name: compile.internal.semantic.canonical_type_in_package(parameter.type_name, ctx.pkg, ctx.generic_names, ctx.declarations) })
        i = i + 1
    }
    ctx
}

func ca_receiver_identity(string type_name, string pkg) string {
    clean := compile.internal.typesys.parse_type(type_name)
    for te_starts_with(clean, "&") || te_starts_with(clean, "*") { clean = prelude_slice(clean, 1, len(clean)); if te_starts_with(clean, "mut") { clean = prelude_slice(clean, 3, len(clean)) } }
    for te_ends_with(clean, "*") { clean = prelude_slice(clean, 0, len(clean)-1) }
    base := compile.internal.typesys.base_type_name(clean)
    if te_starts_with(base, pkg + ".") { return clean }
    // Declaration methods belong to their package. The checker already selected
    // the exact receiver binding, so this is qualification rather than guessing.
    return pkg + "." + clean
}

// Receiver declarations become ordinary functions after specialization, with
// the checked receiver made an explicit first parameter. Call finalization has
// already inserted the matching receiver operand and nominal method identity.
func flatten_canonical_methods(source_file original) canonical_annotation_result {
    file := original; i := 0
    for i < len(file.items) {
        switch file.items[i] {
            item.method(method): {
                if len(method.method.sig.generics) != 0 || mono_receiver_has_parameter(method.receiver_type, file) { return canonical_annotation_result { file: file, error: "receiver method still has generic parameters: " + method.method.sig.name } }
                pkg := te_package(file, i)
                owner := ca_receiver_identity(method.receiver_type, pkg)
                if te_starts_with(owner, pkg + ".") { owner = prelude_slice(owner, len(pkg)+1, len(owner)) }
                function := method.method
                function.sig.name = owner + "." + function.sig.name
                parameters := compile.internal.ast.param[]()
                parameters = append(parameters, compile.internal.ast.param { name: method.receiver_name, type_name: method.receiver_type })
                p := 0
                for p < len(function.sig.params) { parameters = append(parameters, function.sig.params[p]); p = p + 1 }
                function.sig.params = parameters
                file.items[i] = item.function(function)
            },
            _: (),
        }
        i = i + 1
    }
    canonical_annotation_result { file: file, error: "" }
}
