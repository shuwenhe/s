package compile.internal.mono
import (
    "compile.internal.ast"
    "compile.internal.semantic"
    "compile.internal.typesys"
    "s"
    "std.option"
    "std.prelude"
)

struct generic_instance_key {
    string function_name
    string[] type_args
}

struct mono_instance {
    string item_kind
    string receiver_type
    string generic_name
    string instance_name
    string[] type_args
}

struct mono_cache {
    mono_instance[] instances
}

struct mono_cache_result {
    mono_cache cache
    string instance_name
}

struct mono_ownership_summary {
    string type_name
    string ownership
    bool copy
    bool drop
}

struct mono_function_summary {
    string instance_name
    mono_ownership_summary[] params
    mono_ownership_summary result
}

struct monomorphize_file_result {
    string error
    file source_file
    mono_cache cache
    int invariant_errors
    m1_identity_verification m1_gate
}

struct mono_work_item {
    string item_kind
    string receiver_type
    string generic_name
    string[] type_args
    compile.internal.semantic.declaration_ref declaration_ref
    int declaration_index
}

struct mono_context {
    mono_cache cache
    mono_work_item[] worklist
    string[] processed
    compile.internal.semantic.declaration_ref[] declarations
    string[] input_names
    string[] input_receivers
    string[] input_packages
    string current_package
    int errors
    string error
}

func new_context() mono_context {
    mono_context {
        cache: new_cache(),
        worklist: mono_work_item[] {},
        processed: string[] {},
        declarations: compile.internal.semantic.declaration_ref[] {},
    }
}

func new_context_with_result(semantic_result result) mono_context {
    mono_context {
        cache: new_cache(),
        worklist: mono_work_item[] {},
        processed: string[] {},
        declarations: result.declarations,
    }
}

func mono_work_key(string item_kind, string receiver_type, string generic_name, string[] type_args) string {
    key := item_kind + ":" + receiver_type + ":" + generic_name
    i := 0
    for i < len(type_args) {
        key = key + ":" + type_args[i]
        i = i + 1
    }
    key
}

func is_work_processed(mono_context ctx, string item_kind, string receiver_type, string generic_name, string[] type_args) bool {
    key := mono_work_key(item_kind, receiver_type, generic_name, type_args)
    i := 0
    for i < len(ctx.processed) {
        if ctx.processed[i] == key {
            return true
        }
        i = i + 1
    }
    false
}

func mark_work_processed(mono_context ctx, string item_kind, string receiver_type, string generic_name, string[] type_args) mono_context {
    key := mono_work_key(item_kind, receiver_type, generic_name, type_args)
    ctx.processed = append(ctx.processed, key)
    ctx
}

func new_cache() mono_cache {
    mono_cache { instances: mono_instance[] {} }
}

func make_instance_key(string generic_name, string[] type_args) generic_instance_key {
    generic_instance_key { function_name: generic_name, type_args: type_args }
}

func make_instance_name(string generic_name, string[] type_args) string {
    name := generic_name + "__mono"
    i := 0
    for i < len(type_args) {
        name = name + "_" + encode_type(type_args[i])
        i = i + 1
    }
    name
}

func encode_type(string type_name) string {
    out := ""
    i := 0
    for i < len(type_name) {
        ch := std.prelude.char_at(type_name, i)
        if ch == "&" { out = out + "ref"
        } else if ch == "[" { out = out + "arr"
        } else if ch == "]" { out = out + "end"
        } else if ch == "," || ch == " " { out = out + "_"
        } else { out = out + ch }
        i = i + 1
    }
    if out == "" { return "unknown" }
    out
}

func same_type_args(string[] left, string[] rhs) bool {
    if len(left) != len(rhs) { return false }
    i := 0
    for i < len(left) {
        if !compile.internal.typesys.same_type(left[i], rhs[i]) { return false }
        i = i + 1
    }
    true
}

func mono_cache_lookup(mono_cache cache, string generic_name, string[] type_args) string {
    mono_cache_lookup_item(cache, "function", "", generic_name, type_args)
}

func mono_cache_lookup_item(mono_cache cache, string item_kind, string receiver_type, string generic_name, string[] type_args) string {
    i := 0
    for i < len(cache.instances) {
        instance := cache.instances[i]
        if instance.item_kind == item_kind && instance.receiver_type == receiver_type && instance.generic_name == generic_name && same_type_args(instance.type_args, type_args) {
            return instance.instance_name
        }
        i = i + 1
    }
    ""
}

func mono_cache_lookup_key(mono_cache cache, generic_instance_key key) string {
    mono_cache_lookup(cache, key.function_name, key.type_args)
}

func mono_cache_get_or_create(mono_cache cache, string generic_name, string[] type_args) mono_cache_result {
    mono_cache_get_or_create_item(cache, "function", "", generic_name, type_args)
}

func mono_cache_get_or_create_item(mono_cache cache, string item_kind, string receiver_type, string generic_name, string[] type_args) mono_cache_result {
    existing := mono_cache_lookup_item(cache, item_kind, receiver_type, generic_name, type_args)
    if existing != "" { return mono_cache_result { cache: cache, instance_name: existing } }
    name := make_instance_name(generic_name, type_args)
    cache.instances = append(cache.instances, mono_instance {
        item_kind: item_kind,
        receiver_type: receiver_type,
        generic_name: generic_name,
        instance_name: name,
        type_args: type_args,
    })
    mono_cache_result { cache: cache, instance_name: name }
}

func mono_cache_get_or_create_key(mono_cache cache, generic_instance_key key) mono_cache_result {
    mono_cache_get_or_create(cache, key.function_name, key.type_args)
}

func mono_cache_count(mono_cache cache) int {
    len(cache.instances)
}

func find_declaration_ref_for_item(mono_context ctx, string item_kind, string generic_name) compile.internal.semantic.declaration_ref {
    i := 0
    for i < len(ctx.declarations) {
        decl := ctx.declarations[i]
        
        expected_kind := compile.internal.semantic.declaration_kind.function_kind
        if item_kind == "method" {
            expected_kind = compile.internal.semantic.declaration_kind.method_kind
        } else if item_kind == "struct" {
            expected_kind = compile.internal.semantic.declaration_kind.struct_kind
        }
        
        if decl.kind == expected_kind && (decl.path == generic_name || decl.package_path + "." + decl.path == generic_name) {
            return decl
        }
        i = i + 1
    }
    
    compile.internal.semantic.declaration_ref {
        package_path: "",
        kind: compile.internal.semantic.declaration_kind.function_kind,
        path: generic_name,
    }
}

struct m1_identity_verification {
    bool declarations_received
    int declarations_count
    int work_items_with_ref_count
    int work_items_without_ref_count
    bool all_refs_have_valid_package_path
    bool all_refs_have_valid_kind
    bool all_refs_have_valid_path
    int work_items_with_provable_source
    int work_items_with_untraced_source
    bool all_refs_traced_to_semantic
}

func verify_identity_threading(mono_context ctx) m1_identity_verification {
    verification := m1_identity_verification {
        declarations_received: len(ctx.declarations) > 0,
        declarations_count: len(ctx.declarations),
        work_items_with_ref_count: 0,
        work_items_without_ref_count: 0,
        all_refs_have_valid_package_path: true,
        all_refs_have_valid_kind: true,
        all_refs_have_valid_path: true,
        work_items_with_provable_source: 0,
        work_items_with_untraced_source: 0,
        all_refs_traced_to_semantic: true,
    }
    
    i := 0
    for i < len(ctx.worklist) {
        item := ctx.worklist[i]
        
        if item.declaration_ref.path != "" {
            verification.work_items_with_ref_count = verification.work_items_with_ref_count + 1
            
            if item.declaration_ref.package_path == "" {
                verification.all_refs_have_valid_package_path = false
            }
            if item.declaration_ref.path == "" {
                verification.all_refs_have_valid_path = false
            }
            
            found_in_semantic := false
            j := 0
            for j < len(ctx.declarations) {
                if compile.internal.semantic.declaration_ref_equal(item.declaration_ref, ctx.declarations[j]) {
                    found_in_semantic = true
                    verification.work_items_with_provable_source = verification.work_items_with_provable_source + 1
                    break
                }
                j = j + 1
            }
            
            if !found_in_semantic {
                verification.work_items_with_untraced_source = verification.work_items_with_untraced_source + 1
                verification.all_refs_traced_to_semantic = false
            }
        } else {
            verification.work_items_without_ref_count = verification.work_items_without_ref_count + 1
        }
        i = i + 1
    }
    
    verification
}

func monomorphize_file(source_file file, semantic_result result) monomorphize_file_result {

    ctx := new_context_with_result(result)
    // Keep only lookup metadata in the mutable traversal state. Carrying the
    // AST here snapshots the complete compiler at every recursive visit.
    source_index := 0
    for source_index < len(file.items) {
        name := ""
        receiver := ""
        switch file.items[source_index] {
            item.function(f): name = f.sig.name,
            item.method(m): { name = m.method.sig.name; receiver = m.receiver_type },
            _: (),
        }
        ctx.input_names.push(name)
        ctx.input_receivers.push(receiver)
        ctx.input_packages.push(te_package(file, source_index))
        source_index = source_index + 1
    }
    extra_packages := string[]()
    extra_items := compile.internal.ast.item[]()

    i := 0
    for i < len(file.items) {
        ctx.current_package = te_package(file, i)
        if mono_item_is_concrete(file.items[i], file) { ctx = collect_item_instances_ctx(file.items[i], file.items, ctx) }
        i = i + 1
    }

    cursor := 0
    for cursor < len(ctx.worklist) {
        work := ctx.worklist[cursor]
        cursor = cursor + 1

        if is_work_processed(ctx, work.item_kind, work.receiver_type, work.generic_name, work.type_args) {
            continue
        }
        ctx = mark_work_processed(ctx, work.item_kind, work.receiver_type, work.generic_name, work.type_args)

        if work.item_kind == "method" {
            method_source := find_generic_method(file.items, work.receiver_type, work.generic_name)
            if work.declaration_index >= 0 && work.declaration_index < len(file.items) { switch file.items[work.declaration_index] { item.method(v): method_source = v, _: () } }
            ctx.current_package = te_package(file, work.declaration_index)
            if method_source.method.sig.name == "" {
                continue
            }
            method_instance := specialize_method(method_source, work.type_args)
            ctx = collect_item_instances_ctx(item.method(method_instance), file.items, ctx)
            extra_items = append(extra_items, item.method(finalize_monomorphized_method(method_instance)))
            extra_packages = append(extra_packages, ctx.current_package)
        } else {
            source := find_generic_function(file.items, work.generic_name)
            if work.declaration_index >= 0 && work.declaration_index < len(file.items) { switch file.items[work.declaration_index] { item.function(v): source = v, _: () } }
            ctx.current_package = te_package(file, work.declaration_index)
            if source.sig.name == "" {
                continue
            }

            instance := specialize_function(source, work.type_args)

            ctx = collect_item_instances_ctx(item.function(instance), file.items, ctx)

            extra_items = append(extra_items, item.function(finalize_monomorphized_function(instance)))
            extra_packages = append(extra_packages, ctx.current_package)
        }
    }

    stripped := item[]()
    stripped_packages := string[]()
    i = 0
    for i < len(file.items) {
        if should_keep_after_monomorphization(file.items[i], file) {
            value := file.items[i]
            switch value { item.function(v): value = item.function(finalize_monomorphized_function(v)), item.method(v): value = item.method(finalize_monomorphized_method(v)), _: () }
            stripped = append(stripped, value)
            stripped_packages = append(stripped_packages, te_package(file, i))
        }
        i = i + 1
    }
    file.items = stripped
    file.item_packages = stripped_packages

    i = 0
    for i < len(extra_items) {
        file.items = append(file.items, extra_items[i])
        file.item_packages = append(file.item_packages, extra_packages[i])
        i = i + 1
    }

    m1_verification := verify_identity_threading(ctx)

    monomorphize_file_result { error: ctx.error, file: file, cache: ctx.cache, invariant_errors: verify_monomorphized_file(file) + ctx.errors, m1_gate: m1_verification }
}

func should_keep_after_monomorphization(item value, source_file file) bool {
    switch value {
        item.function(function_value) : len(function_value.sig.generics) == 0,
        item.method(method) : len(method.method.sig.generics) == 0 && !mono_receiver_has_parameter(method.receiver_type, file),
        _ : true,
    }
}

func collect_item_instances_ctx(item value, item[] all_items, mono_context ctx) mono_context {
    switch value {
        item.function(function_value) : {
            switch function_value.body {
                option.some(body) : collect_block_instances_ctx(body, all_items, ctx),
                option.none : ctx,
            }
        }
        item.method(method) : {
            switch method.method.body {
                option.some(body) : collect_block_instances_ctx(body, all_items, ctx),
                option.none : ctx,
            }
        }
        _ : ctx,
    }
}

func collect_block_instances_ctx(block_expr block, item[] all_items, mono_context ctx) mono_context {
	out := ctx
    i := 0
    for i < len(block.statements) {
		out = collect_stmt_instances_ctx(block.statements[i], all_items, out)
        i = i + 1
    }
    switch block.final_expr {
		option.some(value) : out = collect_expr_instances_ctx(value, all_items, out),
        option.none : (),
    }
	out
}

func collect_stmt_instances_ctx(stmt value, item[] all_items, mono_context ctx) mono_context {
    switch value {
        stmt.continue(_) : ctx,
        stmt.break(_) : ctx,
        stmt.let(v) : collect_expr_instances_ctx(v.value, all_items, ctx),
        stmt.assign(v) : collect_expr_instances_ctx(v.value, all_items, ctx),
        stmt.store(v): { out := collect_expr_instances_ctx(v.target, all_items, ctx); collect_expr_instances_ctx(v.value, all_items, out) },
        stmt.multi(v): { out := ctx; i := 0; for i < len(v.targets) { out = collect_expr_instances_ctx(v.targets[i], all_items, out); i = i + 1 }
 collect_expr_instances_ctx(v.value, all_items, out) },
        stmt.increment(_) : ctx,
        stmt.c_for(v) : {
            out := collect_stmt_instances_ctx(v.init.value, all_items, ctx)
            out = collect_expr_instances_ctx(v.condition, all_items, out)
            out = collect_stmt_instances_ctx(v.step.value, all_items, out)
            collect_block_instances_ctx(v.body, all_items, out)
        }
        stmt.return(v) : {
            switch v.value {
                option.some(e) : collect_expr_instances_ctx(e, all_items, ctx),
                option.none : ctx,
            }
        }
        stmt.expr(v) : collect_expr_instances_ctx(v.expr, all_items, ctx),
        stmt.defer(v) : collect_expr_instances_ctx(v.expr, all_items, ctx),
        stmt.sroutine(v) : collect_expr_instances_ctx(v.expr, all_items, ctx),
    }
}

func collect_expr_instances_ctx(expr value, item[] all_items, mono_context ctx) mono_context {
	out := ctx
    switch value {
        expr.record(v): { i := 0; for i < len(v.field_values) { out = collect_expr_instances_ctx(v.field_values[i], all_items, out); i = i + 1 }
 out },
        expr.tuple(v): { i := 0; for i < len(v.items) { out = collect_expr_instances_ctx(v.items[i], all_items, out); i = i + 1 }
 out },
        expr.while(v): { out = collect_expr_instances_ctx(v.condition.value, all_items, out); collect_block_instances_ctx(v.body, all_items, out) },
		expr.borrow(v) : collect_expr_instances_ctx(v.target.value, all_items, out),
        expr.binary(v) : {
			out = collect_expr_instances_ctx(v.left.value, all_items, out)
			collect_expr_instances_ctx(v.right.value, all_items, out)
        }
		expr.member(v) : collect_expr_instances_ctx(v.target.value, all_items, out),
        expr.index(v) : {
			out = collect_expr_instances_ctx(v.target.value, all_items, out)
			collect_expr_instances_ctx(v.index.value, all_items, out)
        }
        expr.call(v) : {
			out = collect_method_call_instance_ctx(v, all_items, out)
			out = collect_call_instance_ctx(v, all_items, out)
            i := 0
            for i < len(v.args) {
				out = collect_expr_instances_ctx(v.args[i], all_items, out)
                i = i + 1
            }
			collect_expr_instances_ctx(v.callee.value, all_items, out)
        }
        expr.if(v) : {
			out = collect_expr_instances_ctx(v.condition.value, all_items, out)
			out = collect_block_instances_ctx(v.then_branch, all_items, out)
            switch v.else_branch {
				option.some(e) : collect_expr_instances_ctx(e.value, all_items, out),
				option.none : out,
            }
        }
		expr.for(v) : collect_for_instances_ctx(v, all_items, out),
		expr.block(v) : collect_block_instances_ctx(v, all_items, out),
        expr.switch(v) : {
			out = collect_expr_instances_ctx(v.subject.value, all_items, out)
            i := 0
            for i < len(v.arms) {
				out = collect_expr_instances_ctx(v.arms[i].expr, all_items, out)
                i = i + 1
            }
			out
        }
        expr.array(v) : {
            i := 0
            for i < len(v.items) {
				out = collect_expr_instances_ctx(v.items[i], all_items, out)
                i = i + 1
            }
			out
        }
        expr.map(v) : {
            i := 0
            for i < len(v.entries) {
				out = collect_expr_instances_ctx(v.entries[i].key, all_items, out)
				out = collect_expr_instances_ctx(v.entries[i].value, all_items, out)
                i = i + 1
            }
			out
        }
		_ : out,
    }
}

func collect_call_instance_ctx(compile.internal.ast.call_expr call, item[] all_items, mono_context ctx) mono_context {
    generic_name := compile.internal.semantic.qualified_expr_path(call.callee.value)
    // Semantic and MIR give these exact unqualified builtins their own typed
    // operations, even when a generic prelude declaration is also in scope.
    if (generic_name == "len" || generic_name == "append") && len(call.type_args) == 0 && call.resolved_callee.is_none() { return ctx }
    source := find_generic_function(all_items, generic_name)
    declaration_index := mono_find_work_index(ctx, generic_name, "")
    if declaration_index >= 0 && declaration_index < len(all_items) {
        switch all_items[declaration_index] { item.function(v): source = v, _: () }
        generic_name = ctx.input_packages[declaration_index] + "." + source.sig.name
    }
    if source.sig.name == "" || len(source.sig.generics) == 0 {
        return ctx
    }

    if len(call.type_args) != len(source.sig.generics) { ctx.errors = ctx.errors + 1; ctx.error = "missing concrete type arguments for " + generic_name; return ctx }
    switch call.resolved_callee { option.some(identity): (), option.none: { ctx.errors = ctx.errors + 1; ctx.error = "missing resolved declaration for " + generic_name; return ctx } }
    existing := mono_cache_lookup_item(ctx.cache, "function", "", generic_name, call.type_args)
    result := mono_cache_get_or_create_item(ctx.cache, "function", "", generic_name, call.type_args)
    ctx.cache = result.cache

    if existing == "" {
        decl_ref := find_declaration_ref_for_item(ctx, "function", generic_name)
        ctx.worklist = append(ctx.worklist, mono_work_item { item_kind: "function", receiver_type: "", generic_name: generic_name, type_args: call.type_args, declaration_ref: decl_ref, declaration_index: declaration_index })
    }

    ctx
}

func collect_method_call_instance_ctx(compile.internal.ast.call_expr call, item[] all_items, mono_context ctx) mono_context {
    if len(call.type_args) == 0 {
        return ctx
    }

    method_name := ""
    receiver_type := ""
    switch call.callee.value {
        expr.member(member) : {
            method_name = member.member
            switch member.target.value {
                expr.name(name) : {
                    switch name.inferred_type {
                        option.some(ty) : receiver_type = ty,
                        option.none : (),
                    }
                }
                expr.member(target_member) : {
                    switch target_member.inferred_type {
                        option.some(ty) : receiver_type = ty,
                        option.none : (),
                    }
                }
                _ : (),
            }
        }
        _ : return ctx,
    }

    if receiver_type == "" {
        return ctx
    }

    source := find_generic_method(all_items, receiver_type, method_name)
    if source.method.sig.name == "" {
        return ctx
    }

    existing := mono_cache_lookup_item(ctx.cache, "method", source.receiver_type, method_name, call.type_args)
    result := mono_cache_get_or_create_item(ctx.cache, "method", source.receiver_type, method_name, call.type_args)
    ctx.cache = result.cache

    if existing == "" {
        decl_ref := find_declaration_ref_for_item(ctx, "method", method_name)
        ctx.worklist = append(ctx.worklist, mono_work_item { item_kind: "method", receiver_type: source.receiver_type, generic_name: method_name, type_args: call.type_args, declaration_ref: decl_ref, declaration_index: mono_find_work_index(ctx, method_name, source.receiver_type) })
    }

    ctx
}

func collect_for_instances_ctx(for_expr v, item[] all_items, mono_context ctx) mono_context {
	out := ctx
    switch v.init {
		option.some(s) : out = collect_stmt_instances_ctx(s.value, all_items, out),
        option.none : (),
    }
    switch v.condition {
		option.some(e) : out = collect_expr_instances_ctx(e.value, all_items, out),
        option.none : (),
    }
    switch v.post {
        option.some(s) : out = collect_stmt_instances_ctx(s.value, all_items, out),
        option.none : (),
    }
    switch v.iterable {
        option.some(e) : out = collect_expr_instances_ctx(e.value, all_items, out),
        option.none : (),
    }
    collect_block_instances_ctx(v.body, all_items, out)
}

func collect_item_instances(item value, item[] all_items, mono_cache cache, mono_work_item[] worklist) mono_cache {
    switch value {
        item.function(function_value) : {
            switch function_value.body {
                option.some(body) : collect_block_instances(body, all_items, cache, worklist),
                option.none : cache,
            }
        }
        item.method(method) : {
            switch method.method.body {
                option.some(body) : collect_block_instances(body, all_items, cache, worklist),
                option.none : cache,
            }
        }
        _ : cache,
    }
}

func collect_block_instances(block_expr block, item[] all_items, mono_cache cache, mono_work_item[] worklist) mono_cache {
	out := cache
    i := 0
    for i < len(block.statements) {
		out = collect_stmt_instances(block.statements[i], all_items, out, worklist)
        i = i + 1
    }
    switch block.final_expr {
		option.some(value) : out = collect_expr_instances(value, all_items, out, worklist),
        option.none : (),
    }
	out
}

func collect_stmt_instances(stmt value, item[] all_items, mono_cache cache, mono_work_item[] worklist) mono_cache {
    switch value {
        stmt.store(v) : {
            out := collect_expr_instances(v.target, all_items, cache, worklist)
            collect_expr_instances(v.value, all_items, out, worklist)
        }
        stmt.multi(v) : {
            out := cache
            i := 0
            for i < len(v.targets) { out = collect_expr_instances(v.targets[i], all_items, out, worklist); i = i + 1 }
            collect_expr_instances(v.value, all_items, out, worklist)
        }
        stmt.continue(_) : cache,
        stmt.break(_) : cache,
        stmt.let(v) : collect_expr_instances(v.value, all_items, cache, worklist),
        stmt.assign(v) : collect_expr_instances(v.value, all_items, cache, worklist),
        stmt.increment(_) : cache,
        stmt.c_for(v) : {
            out := collect_stmt_instances(v.init.value, all_items, cache, worklist)
            out = collect_expr_instances(v.condition, all_items, out, worklist)
            out = collect_stmt_instances(v.step.value, all_items, out, worklist)
            collect_block_instances(v.body, all_items, out, worklist)
        }
        stmt.return(v) : {
            switch v.value {
                option.some(e) : collect_expr_instances(e, all_items, cache, worklist),
                option.none : cache,
            }
        }
        stmt.expr(v) : collect_expr_instances(v.expr, all_items, cache, worklist),
        stmt.defer(v) : collect_expr_instances(v.expr, all_items, cache, worklist),
        stmt.sroutine(v) : collect_expr_instances(v.expr, all_items, cache, worklist),
    }
}

func collect_expr_instances(expr value, item[] all_items, mono_cache cache, mono_work_item[] worklist) mono_cache {
	out := cache
    switch value {
		expr.borrow(v) : collect_expr_instances(v.target.value, all_items, out, worklist),
        expr.binary(v) : {
			out = collect_expr_instances(v.left.value, all_items, out, worklist)
			collect_expr_instances(v.right.value, all_items, out, worklist)
        }
		expr.member(v) : collect_expr_instances(v.target.value, all_items, out, worklist),
        expr.index(v) : {
			out = collect_expr_instances(v.target.value, all_items, out, worklist)
			collect_expr_instances(v.index.value, all_items, out, worklist)
        }
        expr.call(v) : {
            out = collect_call_instance(v, all_items, out, worklist)
            i := 0
            for i < len(v.args) {
                out = collect_expr_instances(v.args[i], all_items, out, worklist)
                i = i + 1
            }
            collect_expr_instances(v.callee.value, all_items, out, worklist)
        }
        expr.if(v) : {
            out = collect_expr_instances(v.condition.value, all_items, out, worklist)
            out = collect_block_instances(v.then_branch, all_items, out, worklist)
            switch v.else_branch {
                option.some(e) : collect_expr_instances(e.value, all_items, out, worklist),
                option.none : out,
            }
        }
        expr.for(v) : collect_for_instances(v, all_items, out, worklist),
        expr.block(v) : collect_block_instances(v, all_items, out, worklist),
        expr.switch(v) : {
            out = collect_expr_instances(v.subject.value, all_items, out, worklist)
            i := 0
            for i < len(v.arms) {
                out = collect_expr_instances(v.arms[i].expr, all_items, out, worklist)
                i = i + 1
            }
            out
        }
        expr.array(v) : {
            i := 0
            for i < len(v.items) {
                out = collect_expr_instances(v.items[i], all_items, out, worklist)
                i = i + 1
            }
            out
        }
        expr.map(v) : {
            i := 0
            for i < len(v.entries) {
                out = collect_expr_instances(v.entries[i].key, all_items, out, worklist)
                out = collect_expr_instances(v.entries[i].value, all_items, out, worklist)
                i = i + 1
            }
            out
        }
        _ : out,
    }
}

func collect_call_instance(compile.internal.ast.call_expr call, item[] all_items, mono_cache cache, mono_work_item[] worklist) mono_cache {
	out := cache
    if len(call.type_args) == 0 {
        return cache
    }
    resolved := ""
    switch call.resolved_callee {
        option.some(name) : resolved = name,
        option.none : return cache,
    }
    generic_name := ""
    switch call.callee.value {
        expr.name(name) : generic_name = name.name,
        _ : return cache,
    }
    source := find_generic_function(all_items, generic_name)
    if source.sig.name == "" {
        return cache
    }
    existing := mono_cache_lookup(out, generic_name, call.type_args)
    result := mono_cache_get_or_create(out, generic_name, call.type_args)
    out = result.cache
    /* Work items are appended by the context-aware collector. */
    out
}

func collect_for_instances(for_expr v, item[] all_items, mono_cache cache, mono_work_item[] worklist) mono_cache {
    out := cache
    switch v.init {
        option.some(s) : out = collect_stmt_instances(s.value, all_items, out, worklist),
        option.none : (),
    }
    switch v.condition {
        option.some(e) : out = collect_expr_instances(e.value, all_items, out, worklist),
        option.none : (),
    }
    switch v.post {
        option.some(s) : out = collect_stmt_instances(s.value, all_items, out, worklist),
        option.none : (),
    }
    switch v.iterable {
        option.some(e) : out = collect_expr_instances(e.value, all_items, out, worklist),
        option.none : (),
    }
    collect_block_instances(v.body, all_items, out, worklist)
}

func find_generic_function(item[] items, string name) function_decl {
    i := 0
    for i < len(items) {
        switch items[i] {
            item.function(function_value) : {
                if function_value.sig.name == name && len(function_value.sig.generics) > 0 {
                    return function_value
                }
            }
            _ : (),
        }
        i = i + 1
    }
    return function_decl {}
}

func find_generic_method(item[] items, string receiver_type, string name) receiver_method_decl {
    target_owner := compile.internal.typesys.base_type_name(receiver_type)
    i := 0
    for i < len(items) {
        switch items[i] {
            item.method(method) : {
                method_owner := compile.internal.typesys.base_type_name(method.receiver_type)
                if method_owner == target_owner && method.method.sig.name == name && len(method_generic_names(method)) > 0 {
                    return method
                }
            }
            _ : (),
        }
        i = i + 1
    }
    return receiver_method_decl {}
}

func verify_monomorphized_file(source_file file) int {
    errors := 0
    i := 0
    for i < len(file.items) {
        switch file.items[i] {
            item.function(function_value) : {
                if len(function_value.sig.generics) == 0 && mono_contains_text(function_value.sig.name, "__mono") {
                    errors = errors + verify_function_no_generics(function_value)
                }
            }
            item.method(method) : {
                if len(method.method.sig.generics) == 0 && mono_contains_text(method.method.sig.name, "__mono") {
                    errors = errors + verify_function_no_generics(method.method)
                }
            }
            _ : (),
        }
        i = i + 1
    }
    errors
}

func no_mono_expr() option[expr] {
    return option.none
}

func no_mono_box_expr() option[box[expr]] {
    return option.none
}

func no_mono_box_stmt() option[box[stmt]] {
    return option.none
}

func no_mono_body() option[block_expr] {
    return option.none
}

func finalize_monomorphized_function(function_decl function_value) function_decl {
    body := no_mono_body()
    switch function_value.body {
        option.some(value) : body = option.some(finalize_block(value)),
        option.none : (),
    }
    function_decl { intrinsic_name: function_value.intrinsic_name, extern_library: function_value.extern_library, sig: function_value.sig, body body, is_public: function_value.is_public }
}

func finalize_monomorphized_method(receiver_method_decl method) receiver_method_decl {
    receiver_method_decl {
        receiver_name: method.receiver_name,
        receiver_type: method.receiver_type,
        method: finalize_monomorphized_function(method.method),
    }
}

func finalize_block(block_expr block) block_expr {
    stmts := stmt[]()
    i := 0
    for i < len(block.statements) {
        stmts = append(stmts, finalize_stmt(block.statements[i]))
        i = i + 1
    }
    final_expr := no_mono_expr()
    switch block.final_expr {
        option.some(value) : final_expr = option.some(finalize_expr(value)),
        option.none : (),
    }
    block_expr { statements: stmts, final_expr: final_expr, inferred_type: block.inferred_type }
}

func finalize_stmt(stmt value) stmt {
    switch value {
        stmt.continue(_) : value,
        stmt.break(_) : value,
        stmt.let(v) : stmt.let(var_stmt { name: v.name, type_name: v.type_name, value: finalize_expr(v.value) }),
        stmt.assign(v) : stmt.assign(compile.internal.ast.assign_stmt { name: v.name, value: finalize_expr(v.value) }),
        stmt.store(v): { v.target = finalize_expr(v.target); v.value = finalize_expr(v.value); stmt.store(v) },
        stmt.multi(v): { i := 0; for i < len(v.targets) { v.targets[i] = finalize_expr(v.targets[i]); i = i + 1 }
 v.value = finalize_expr(v.value); stmt.multi(v) },
        stmt.increment(v) : stmt.increment(v),
        stmt.c_for(v) : stmt.c_for(c_for_stmt { init: std.prelude.box(finalize_stmt(v.init.value)), condition: finalize_expr(v.condition), step: std.prelude.box(finalize_stmt(v.step.value)), body: finalize_block(v.body) }),
        stmt.return(v) : {
            ret := no_mono_expr()
            switch v.value {
                option.some(e) : ret = option.some(finalize_expr(e)),
                option.none : (),
            }
            stmt.return(compile.internal.ast.return_stmt { value: ret })
        }
        stmt.expr(v) : stmt.expr(compile.internal.ast.expr_stmt { expr: finalize_expr(v.expr) }),
        stmt.defer(v) : stmt.defer(defer_stmt { expr: finalize_expr(v.expr) }),
        stmt.sroutine(v) : stmt.sroutine(sroutine_stmt { expr: finalize_expr(v.expr) }),
    }
}

func finalize_expr(expr value) expr {
    switch value {
        expr.int(v) : expr.int(v),
        expr.string(v) : expr.string(v),
        expr.bool(v) : expr.bool(v),
        expr.name(v) : expr.name(v),
        expr.record(v): { i := 0; for i < len(v.field_values) { v.field_values[i] = finalize_expr(v.field_values[i]); i = i + 1 }
 expr.record(v) },
        expr.tuple(v): { i := 0; for i < len(v.items) { v.items[i] = finalize_expr(v.items[i]); i = i + 1 }
 expr.tuple(v) },
        expr.borrow(v) : expr.borrow(compile.internal.ast.borrow_expr { target: std.prelude.box(finalize_expr(v.target.value)), mutable v.mutable, inferred_type v.inferred_type }),
        expr.binary(v) : expr.binary(compile.internal.ast.binary_expr { left: std.prelude.box(finalize_expr(v.left.value)), op v.op, right std.prelude.box(finalize_expr(v.right.value)), inferred_type v.inferred_type }),
        expr.member(v) : expr.member(compile.internal.ast.member_expr { target: std.prelude.box(finalize_expr(v.target.value)), member v.member, inferred_type v.inferred_type }),
        expr.index(v) : expr.index(compile.internal.ast.index_expr { target: std.prelude.box(finalize_expr(v.target.value)), index std.prelude.box(finalize_expr(v.index.value)), inferred_type v.inferred_type }),
        expr.call(v) : {
            args := expr[]()
            i := 0
            for i < len(v.args) {
                args = append(args, finalize_expr(v.args[i]))
                i = i + 1
            }
            callee := finalize_expr(v.callee.value)
            switch v.callee.value {
                expr.member(member): {
                    receiver_type := mono_expression_type(member.target.value)
                    if receiver_type != "" && receiver_type != "module" && v.resolved_callee.is_some() {
                        receiver_args := expr[](); receiver_args = append(receiver_args, finalize_expr(member.target.value)); ai := 0
                        for ai < len(args) { receiver_args = append(receiver_args, args[ai]); ai = ai + 1 }
                        args = receiver_args
                        callee = expr.name(name_expr { name: v.resolved_callee.unwrap(), inferred_type: option.none })
                    }
                },
                _: (),
            }
            expr.call(compile.internal.ast.call_expr { callee: std.prelude.box(callee), args: args, inferred_type: v.inferred_type, resolved_callee: v.resolved_callee, type_args: string[]() })
        }
        expr.if(v) : {
            else_branch := no_mono_box_expr()
            switch v.else_branch {
                option.some(e) : else_branch = option.some(std.prelude.box(finalize_expr(e.value))),
                option.none : (),
            }
            expr.if(if_expr { condition: std.prelude.box(finalize_expr(v.condition.value)), then_branch finalize_block(v.then_branch), else_branch else_branch, inferred_type v.inferred_type })
        }
        expr.for(v) : finalize_for_expr(v),
        expr.while(v) : expr.while(while_expr { condition: std.prelude.box(finalize_expr(v.condition.value)), body finalize_block(v.body), inferred_type v.inferred_type }),
        expr.block(v) : expr.block(finalize_block(v)),
        expr.switch(v) : {
            arms := switch_arm[]()
            i := 0
            for i < len(v.arms) {
                arms = append(arms, switch_arm { pattern: v.arms[i].pattern, expr finalize_expr(v.arms[i].expr) })
                i = i + 1
            }
            expr.switch(switch_expr { subject: std.prelude.box(finalize_expr(v.subject.value)), arms arms, inferred_type v.inferred_type })
        }
        expr.array(v) : {
            items := expr[]()
            i := 0
            for i < len(v.items) {
                items = append(items, finalize_expr(v.items[i]))
                i = i + 1
            }
            expr.array(array_literal { type_text: v.type_text, items items })
        }
        expr.map(v) : {
            entries := map_entry[]()
            i := 0
            for i < len(v.entries) {
                entries = append(entries, map_entry { key: finalize_expr(v.entries[i].key), value finalize_expr(v.entries[i].value) })
                i = i + 1
            }
            expr.map(map_literal { type_text: v.type_text, entries entries })
        }
    }
}

func finalize_for_expr(for_expr v) expr {
    init := no_mono_box_stmt()
    switch v.init {
        option.some(s) : init = option.some(std.prelude.box(finalize_stmt(s.value))),
        option.none : (),
    }
    condition := no_mono_box_expr()
    switch v.condition {
        option.some(e) : condition = option.some(std.prelude.box(finalize_expr(e.value))),
        option.none : (),
    }
    post := no_mono_box_stmt()
    switch v.post {
        option.some(s) : post = option.some(std.prelude.box(finalize_stmt(s.value))),
        option.none : (),
    }
    iterable := no_mono_box_expr()
    switch v.iterable {
        option.some(e) : iterable = option.some(std.prelude.box(finalize_expr(e.value))),
        option.none : (),
    }
    expr.for(for_expr { init: init, condition: condition, post: post, names: v.names, iterable: iterable, body: finalize_block(v.body), inferred_type: v.inferred_type })
}

func verify_function_no_generics(function_decl function_value) int {
    errors := 0
    i := 0
    for i < len(function_value.sig.params) {
        if looks_like_generic_residue(function_value.sig.params[i].type_name) {
            errors = errors + 1
        }
        i = i + 1
    }
    switch function_value.sig.return_type {
        option.some(ty) : {
            if looks_like_generic_residue(ty) {
                errors = errors + 1
            }
        }
        option.none : (),
    }
    switch function_value.body {
        option.some(body) : errors = errors + verify_block_no_generics(body),
        option.none : (),
    }
    errors
}

func verify_block_no_generics(block_expr block) int {
    errors := 0
    i := 0
    for i < len(block.statements) {
        errors = errors + verify_stmt_no_generics(block.statements[i])
        i = i + 1
    }
    switch block.final_expr {
        option.some(value) : errors = errors + verify_expr_no_generics(value),
        option.none : (),
    }
    errors = errors + verify_optional_type_no_generics(block.inferred_type)
    errors
}

func verify_stmt_no_generics(stmt value) int {
    switch value {
        stmt.continue(_) : 0,
        stmt.break(_) : 0,
        stmt.let(v) : verify_optional_type_no_generics(v.type_name) + verify_expr_no_generics(v.value),
        stmt.assign(v) : verify_expr_no_generics(v.value),
        stmt.store(v): verify_expr_no_generics(v.target) + verify_expr_no_generics(v.value),
        stmt.multi(v): { errors := verify_expr_no_generics(v.value); i := 0; for i < len(v.targets) { errors = errors + verify_expr_no_generics(v.targets[i]); i = i + 1 }
 errors },
        stmt.increment(_) : 0,
        stmt.c_for(v) : verify_stmt_no_generics(v.init.value) + verify_expr_no_generics(v.condition) + verify_stmt_no_generics(v.step.value) + verify_block_no_generics(v.body),
        stmt.return(v) : {
            switch v.value {
                option.some(e) : verify_expr_no_generics(e),
                option.none : 0,
            }
        }
        stmt.expr(v) : verify_expr_no_generics(v.expr),
        stmt.defer(v) : verify_expr_no_generics(v.expr),
        stmt.sroutine(v) : verify_expr_no_generics(v.expr),
    }
}

func verify_expr_no_generics(expr value) int {
    switch value {
        expr.int(v) : verify_optional_type_no_generics(v.inferred_type),
        expr.string(v) : verify_optional_type_no_generics(v.inferred_type),
        expr.bool(v) : verify_optional_type_no_generics(v.inferred_type),
        expr.name(v) : verify_optional_type_no_generics(v.inferred_type),
        expr.record(v): { errors := verify_optional_type_no_generics(v.inferred_type); if looks_like_generic_residue(v.type_name) { errors = errors + 1 }
 i := 0; for i < len(v.field_values) { errors = errors + verify_expr_no_generics(v.field_values[i]); i = i + 1 }
 errors },
        expr.tuple(v): { errors := verify_optional_type_no_generics(v.inferred_type); i := 0; for i < len(v.items) { errors = errors + verify_expr_no_generics(v.items[i]); i = i + 1 }
 errors },
        expr.borrow(v) : verify_optional_type_no_generics(v.inferred_type) + verify_expr_no_generics(v.target.value),
        expr.binary(v) : verify_optional_type_no_generics(v.inferred_type) + verify_expr_no_generics(v.left.value) + verify_expr_no_generics(v.right.value),
        expr.member(v) : verify_optional_type_no_generics(v.inferred_type) + verify_expr_no_generics(v.target.value),
        expr.index(v) : verify_optional_type_no_generics(v.inferred_type) + verify_expr_no_generics(v.target.value) + verify_expr_no_generics(v.index.value),
        expr.call(v) : verify_call_no_generics(v),
        expr.if(v) : {
            errors := verify_optional_type_no_generics(v.inferred_type) + verify_expr_no_generics(v.condition.value) + verify_block_no_generics(v.then_branch)
            switch v.else_branch {
                option.some(e) : errors = errors + verify_expr_no_generics(e.value),
                option.none : (),
            }
            errors
        }
        expr.for(v) : verify_for_no_generics(v),
        expr.while(v) : verify_optional_type_no_generics(v.inferred_type) + verify_expr_no_generics(v.condition.value) + verify_block_no_generics(v.body),
        expr.block(v) : verify_block_no_generics(v),
        expr.switch(v) : {
            errors := verify_optional_type_no_generics(v.inferred_type) + verify_expr_no_generics(v.subject.value)
            i := 0
            for i < len(v.arms) {
                errors = errors + verify_expr_no_generics(v.arms[i].expr)
                i = i + 1
            }
            errors
        }
        expr.array(v) : {
            errors := verify_optional_type_no_generics(v.type_text)
            i := 0
            for i < len(v.items) {
                errors = errors + verify_expr_no_generics(v.items[i])
                i = i + 1
            }
            errors
        }
        expr.map(v) : {
            errors := verify_optional_type_no_generics(v.type_text)
            i := 0
            for i < len(v.entries) {
                errors = errors + verify_expr_no_generics(v.entries[i].key)
                errors = errors + verify_expr_no_generics(v.entries[i].value)
                i = i + 1
            }
            errors
        }
    }
}

func verify_call_no_generics(compile.internal.ast.call_expr v) int {
    errors := verify_optional_type_no_generics(v.inferred_type)
    if len(v.type_args) > 0 {
        errors = errors + 1
    }
    errors = errors + verify_expr_no_generics(v.callee.value)
    i := 0
    for i < len(v.args) {
        errors = errors + verify_expr_no_generics(v.args[i])
        i = i + 1
    }
    errors
}

func verify_for_no_generics(for_expr v) int {
    errors := verify_optional_type_no_generics(v.inferred_type)
    switch v.init {
        option.some(s) : errors = errors + verify_stmt_no_generics(s.value),
        option.none : (),
    }
    switch v.condition {
        option.some(e) : errors = errors + verify_expr_no_generics(e.value),
        option.none : (),
    }
    switch v.post {
        option.some(s) : errors = errors + verify_stmt_no_generics(s.value),
        option.none : (),
    }
    switch v.iterable {
        option.some(e) : errors = errors + verify_expr_no_generics(e.value),
        option.none : (),
    }
    errors + verify_block_no_generics(v.body)
}

func verify_optional_type_no_generics(option[string] type_name) int {
    switch type_name {
        option.some(ty) : {
            if looks_like_generic_residue(ty) { return 1 }
            0
        }
        option.none : 0,
    }
}

func looks_like_generic_residue(string type_name) bool {
    clean := type_name
    if clean == "T" || clean == "U" || clean == "V" {
        return true
    }
    contains_generic_atom(clean, "T") || contains_generic_atom(clean, "U") || contains_generic_atom(clean, "V")
}

func contains_generic_atom(string text, string atom) bool {
    i := 0
    for i < len(text) {
        if prelude_slice(text, i, i + 1) == atom {
            left_ok := i == 0 || !mono_is_ident_char(prelude_slice(text, i - 1, i))
            right_ok := i + 1 >= len(text) || !mono_is_ident_char(prelude_slice(text, i + 1, i + 2))
            if left_ok && right_ok {
                return true
            }
        }
        i = i + 1
    }
    false
}

func mono_is_ident_char(string ch) bool {
    (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z") || (ch >= "0" && ch <= "9") || ch == "_"
}

func substitute_type(string type_name, string[] keys, string[] replacements) string {
    te_rewrite_type(type_name, keys, replacements)
}

func substitute_optional_type(option[string] type_name, string[] generic_names, string[] type_args) option[string] {
    switch type_name {
        option.some(value) : option.some(substitute_type(value, generic_names, type_args)),
        option.none : option.none,
    }
}

func find_char(string text, string needle) int {
    i := 0
    for i < len(text) {
        if std.prelude.char_at(text, i) == needle { return i }
        i = i + 1
    }
    -1
}

func generic_names_from_sig(string[] generics) string[] {
    generic_names := string[] {}
    i := 0
    for i < len(generics) {
        raw := generics[i]
        colon := find_char(raw, ":")
        if colon >= 0 { raw = prelude_slice(raw, 0, colon) }
        generic_names = append(generic_names, raw)
        i = i + 1
    }
    generic_names
}

func method_generic_names(receiver_method_decl source) string[] {
    names := generic_names_from_sig(source.method.sig.generics)
    receiver_names := compile.internal.typesys.extract_type_args(source.receiver_type)
    i := 0
    for i < len(receiver_names) {
        name := receiver_names[i]
        if !compile.internal.typesys.is_builtin_primitive(name) {
            found := false; j := 0
            for j < len(names) { if names[j] == name { found = true }
 j = j + 1 }
            if !found { names = append(names, name) }
        }
        i = i + 1
    }
    names
}

func specialize_function(function_decl source, string[] type_args) function_decl {
    specialize_function_with_names(source, type_args, generic_names_from_sig(source.sig.generics))
}

func specialize_function_with_names(function_decl source, string[] type_args, string[] generic_names) function_decl {
    params := compile.internal.ast.param[] {}
    i := 0
    for i < len(source.sig.params) {
        original := source.sig.params[i]
        params = append(params, compile.internal.ast.param {
            name: original.name,
            type_name: substitute_type(original.type_name, generic_names, type_args),
        })
        i = i + 1
    }
    return_type := substitute_optional_type(source.sig.return_type, generic_names, type_args)
    body := no_mono_body()
    switch source.body {
        option.some(value) : body = option.some(substitute_block(value, generic_names, type_args)),
        option.none : (),
    }
    intrinsic_name := source.intrinsic_name
    if source.extern_library == "intrinsic" && intrinsic_name == "" { intrinsic_name = source.sig.name }
    function_decl {
        intrinsic_name: intrinsic_name,
        extern_library: source.extern_library,
        sig: function_sig {
            name: make_instance_name(source.sig.name, type_args),
            generics: string[] {},
            params: params,
            return_type: return_type,
        },
        body: body,
        is_public: source.is_public,
    }
}

func specialize_method(receiver_method_decl source, string[] type_args) receiver_method_decl {
    generic_names := method_generic_names(source)
    receiver_method_decl {
        receiver_name: source.receiver_name,
        receiver_type: substitute_type(source.receiver_type, generic_names, type_args),
        method: specialize_function_with_names(source.method, type_args, generic_names),
    }
}

func substitute_block(block_expr block, string[] generic_names, string[] type_args) block_expr {
    stmts := stmt[]()
    i := 0
    for i < len(block.statements) {
        stmts = append(stmts, substitute_stmt(block.statements[i], generic_names, type_args))
        i = i + 1
    }
    final_expr := no_mono_expr()
    switch block.final_expr {
        option.some(value) : final_expr = option.some(substitute_expr(value, generic_names, type_args)),
        option.none : (),
    }
    block_expr { statements: stmts, final_expr: final_expr, inferred_type: substitute_optional_type(block.inferred_type, generic_names, type_args) }
}

func substitute_stmt(stmt value, string[] generic_names, string[] type_args) stmt {
    switch value {
        stmt.continue(_) : value,
        stmt.break(_) : value,
        stmt.let(v) : stmt.let(var_stmt { name: v.name, type_name substitute_optional_type(v.type_name, generic_names, type_args), value substitute_expr(v.value, generic_names, type_args) }),
        stmt.assign(v) : stmt.assign(compile.internal.ast.assign_stmt { name: v.name, value substitute_expr(v.value, generic_names, type_args) }),
        stmt.store(v): { v.target = substitute_expr(v.target, generic_names, type_args); v.value = substitute_expr(v.value, generic_names, type_args); stmt.store(v) },
        stmt.multi(v): { i := 0; for i < len(v.targets) { v.targets[i] = substitute_expr(v.targets[i], generic_names, type_args); i = i + 1 }
 v.value = substitute_expr(v.value, generic_names, type_args); stmt.multi(v) },
        stmt.increment(v) : stmt.increment(compile.internal.ast.increment_stmt { name: v.name }),
        stmt.c_for(v) : stmt.c_for(c_for_stmt { init: std.prelude.box(substitute_stmt(v.init.value, generic_names, type_args)), condition substitute_expr(v.condition, generic_names, type_args), step std.prelude.box(substitute_stmt(v.step.value, generic_names, type_args)), body substitute_block(v.body, generic_names, type_args) }),
        stmt.return(v) : {
            ret := no_mono_expr()
            switch v.value {
                option.some(e) : ret = option.some(substitute_expr(e, generic_names, type_args)),
                option.none : (),
            }
            stmt.return(compile.internal.ast.return_stmt { value: ret })
        }
        stmt.expr(v) : stmt.expr(compile.internal.ast.expr_stmt { expr: substitute_expr(v.expr, generic_names, type_args) }),
        stmt.defer(v) : stmt.defer(defer_stmt { expr: substitute_expr(v.expr, generic_names, type_args) }),
        stmt.sroutine(v) : stmt.sroutine(sroutine_stmt { expr: substitute_expr(v.expr, generic_names, type_args) }),
    }
}

func substitute_expr(expr value, string[] generic_names, string[] type_args) expr {
    switch value {
        expr.int(v) : { v.inferred_type = substitute_optional_type(v.inferred_type, generic_names, type_args); expr.int(v) },
        expr.string(v) : { v.inferred_type = substitute_optional_type(v.inferred_type, generic_names, type_args); expr.string(v) },
        expr.bool(v) : { v.inferred_type = substitute_optional_type(v.inferred_type, generic_names, type_args); expr.bool(v) },
        expr.name(v) : { v.inferred_type = substitute_optional_type(v.inferred_type, generic_names, type_args); expr.name(v) },
        expr.record(v): { i := 0; for i < len(v.field_values) { v.field_values[i] = substitute_expr(v.field_values[i], generic_names, type_args); i = i + 1 }
 v.type_name = substitute_type(v.type_name, generic_names, type_args); v.inferred_type = substitute_optional_type(v.inferred_type, generic_names, type_args); expr.record(v) },
        expr.tuple(v): { i := 0; for i < len(v.items) { v.items[i] = substitute_expr(v.items[i], generic_names, type_args); i = i + 1 }
 v.inferred_type = substitute_optional_type(v.inferred_type, generic_names, type_args); expr.tuple(v) },
        expr.borrow(v) : expr.borrow(compile.internal.ast.borrow_expr { target: std.prelude.box(substitute_expr(v.target.value, generic_names, type_args)), mutable v.mutable, inferred_type substitute_optional_type(v.inferred_type, generic_names, type_args) }),
        expr.binary(v) : expr.binary(compile.internal.ast.binary_expr { left: std.prelude.box(substitute_expr(v.left.value, generic_names, type_args)), op v.op, right std.prelude.box(substitute_expr(v.right.value, generic_names, type_args)), inferred_type substitute_optional_type(v.inferred_type, generic_names, type_args) }),
        expr.member(v) : expr.member(compile.internal.ast.member_expr { target: std.prelude.box(substitute_expr(v.target.value, generic_names, type_args)), member v.member, inferred_type substitute_optional_type(v.inferred_type, generic_names, type_args) }),
        expr.index(v) : expr.index(compile.internal.ast.index_expr { target: std.prelude.box(substitute_expr(v.target.value, generic_names, type_args)), index std.prelude.box(substitute_expr(v.index.value, generic_names, type_args)), inferred_type substitute_optional_type(v.inferred_type, generic_names, type_args) }),
        expr.call(v) : {
            args := expr[]()
            i := 0
            for i < len(v.args) {
                args = append(args, substitute_expr(v.args[i], generic_names, type_args))
                i = i + 1
            }
            call_type_args := string[]()
            i = 0
            for i < len(v.type_args) {
                call_type_args = append(call_type_args, substitute_type(v.type_args[i], generic_names, type_args))
                i = i + 1
            }
            resolved := v.resolved_callee
            if len(call_type_args) > 0 {
                switch resolved { option.some(identity): resolved = option.some(make_instance_name(mono_substitute_identity(mono_generic_identity(identity), generic_names, type_args), call_type_args)), option.none: () }
            }
            expr.call(compile.internal.ast.call_expr { callee: std.prelude.box(substitute_expr(v.callee.value, generic_names, type_args)), args args, inferred_type substitute_optional_type(v.inferred_type, generic_names, type_args), resolved_callee resolved, type_args call_type_args })
        }
        expr.if(v) : {
            else_branch := no_mono_box_expr()
            switch v.else_branch {
                option.some(e) : else_branch = option.some(std.prelude.box(substitute_expr(e.value, generic_names, type_args))),
                option.none : (),
            }
            expr.if(if_expr { condition: std.prelude.box(substitute_expr(v.condition.value, generic_names, type_args)), then_branch substitute_block(v.then_branch, generic_names, type_args), else_branch else_branch, inferred_type substitute_optional_type(v.inferred_type, generic_names, type_args) })
        }
        expr.for(v) : substitute_for_expr(v, generic_names, type_args),
        expr.while(v) : expr.while(while_expr { condition: std.prelude.box(substitute_expr(v.condition.value, generic_names, type_args)), body substitute_block(v.body, generic_names, type_args), inferred_type substitute_optional_type(v.inferred_type, generic_names, type_args) }),
        expr.block(v) : expr.block(substitute_block(v, generic_names, type_args)),
        expr.switch(v) : expr.switch(substitute_switch(v, generic_names, type_args)),
        expr.array(v) : substitute_array_expr(v, generic_names, type_args),
        expr.map(v) : substitute_map_expr(v, generic_names, type_args),
    }
}

func substitute_for_expr(for_expr v, string[] generic_names, string[] type_args) expr {
    init := no_mono_box_stmt()
    switch v.init {
        option.some(s) : init = option.some(std.prelude.box(substitute_stmt(s.value, generic_names, type_args))),
        option.none : (),
    }
    condition := no_mono_box_expr()
    switch v.condition {
        option.some(e) : condition = option.some(std.prelude.box(substitute_expr(e.value, generic_names, type_args))),
        option.none : (),
    }
    post := no_mono_box_stmt()
    switch v.post {
        option.some(s) : post = option.some(std.prelude.box(substitute_stmt(s.value, generic_names, type_args))),
        option.none : (),
    }
    iterable := no_mono_box_expr()
    switch v.iterable {
        option.some(e) : iterable = option.some(std.prelude.box(substitute_expr(e.value, generic_names, type_args))),
        option.none : (),
    }
    expr.for(for_expr { init: init, condition: condition, post: post, names: v.names, iterable: iterable, body: substitute_block(v.body, generic_names, type_args), inferred_type: substitute_optional_type(v.inferred_type, generic_names, type_args) })
}

func substitute_switch(switch_expr v, string[] generic_names, string[] type_args) switch_expr {
    arms := switch_arm[]()
    i := 0
    for i < len(v.arms) {
        arms = append(arms, switch_arm { pattern: v.arms[i].pattern, expr substitute_expr(v.arms[i].expr, generic_names, type_args) })
        i = i + 1
    }
    switch_expr { subject: std.prelude.box(substitute_expr(v.subject.value, generic_names, type_args)), arms arms, inferred_type substitute_optional_type(v.inferred_type, generic_names, type_args) }
}

func substitute_array_expr(array_literal v, string[] generic_names, string[] type_args) expr {
    items := expr[]()
    i := 0
    for i < len(v.items) {
        items = append(items, substitute_expr(v.items[i], generic_names, type_args))
        i = i + 1
    }
    expr.array(array_literal { type_text: substitute_optional_type(v.type_text, generic_names, type_args), items items })
}

func substitute_map_expr(map_literal v, string[] generic_names, string[] type_args) expr {
    entries := map_entry[]()
    i := 0
    for i < len(v.entries) {
        entries = append(entries, map_entry { key: substitute_expr(v.entries[i].key, generic_names, type_args), value substitute_expr(v.entries[i].value, generic_names, type_args) })
        i = i + 1
    }
    expr.map(map_literal { type_text: substitute_optional_type(v.type_text, generic_names, type_args), entries entries })
}

func summarize_type(string type_name) mono_ownership_summary {
    mono_ownership_summary {
        type_name: type_name,
        ownership: compile.internal.typesys.ownership_mode(type_name),
        copy: compile.internal.typesys.is_copy_type(type_name),
        drop: compile.internal.typesys.requires_drop(type_name),
    }
}

func summarize_instance(function_decl instance) mono_function_summary {
    params := mono_ownership_summary[] {}
    i := 0
    for i < len(instance.sig.params) {
        params = append(params, summarize_type(instance.sig.params[i].type_name))
        i = i + 1
    }
    result := summarize_type("()")
    if instance.sig.return_type.is_some() {
        result = summarize_type(instance.sig.return_type.unwrap())
    }
    mono_function_summary { instance_name: instance.sig.name, params: params, result: result }
}

func verify_monomorphized_file_with_details(source_file file) int {
    errors := verify_monomorphized_file(file)

    i := 0
    for i < len(file.items) {
        switch file.items[i] {
            item.function(function_value) : {
                if mono_contains_text(function_value.sig.name, "__mono") {

                    errors = errors + verify_function_resolved_calls(function_value)
                }
            }
            _ : (),
        }
        i = i + 1
    }

    errors
}

func verify_function_resolved_calls(function_decl function_value) int {
    errors := 0
    switch function_value.body {
        option.some(body) : errors = verify_block_resolved_calls(body),
        option.none : (),
    }
    errors
}

func verify_block_resolved_calls(block_expr block) int {
    errors := 0
    i := 0
    for i < len(block.statements) {
        errors = errors + verify_stmt_resolved_calls(block.statements[i])
        i = i + 1
    }
    switch block.final_expr {
        option.some(value) : errors = errors + verify_expr_resolved_calls(value),
        option.none : (),
    }
    errors
}

func verify_stmt_resolved_calls(stmt value) int {
    switch value {
        stmt.store(v) : verify_expr_resolved_calls(v.target) + verify_expr_resolved_calls(v.value),
        stmt.multi(v) : {
            errors := verify_expr_resolved_calls(v.value)
            i := 0
            for i < len(v.targets) { errors = errors + verify_expr_resolved_calls(v.targets[i]); i = i + 1 }
            errors
        }
        stmt.continue(_) : 0,
        stmt.break(_) : 0,
        stmt.let(v) : verify_expr_resolved_calls(v.value),
        stmt.assign(v) : verify_expr_resolved_calls(v.value),
        stmt.increment(_) : 0,
        stmt.c_for(v) : verify_stmt_resolved_calls(v.init.value) + verify_expr_resolved_calls(v.condition) + verify_stmt_resolved_calls(v.step.value) + verify_block_resolved_calls(v.body),
        stmt.return(v) : {
            switch v.value {
                option.some(e) : verify_expr_resolved_calls(e),
                option.none : 0,
            }
        }
        stmt.expr(v) : verify_expr_resolved_calls(v.expr),
        stmt.defer(v) : verify_expr_resolved_calls(v.expr),
        stmt.sroutine(v) : verify_expr_resolved_calls(v.expr),
    }
}

func verify_expr_resolved_calls(expr value) int {
    switch value {
        expr.call(v) : {
            errors := 0

            if len(v.type_args) == 0 {
                switch v.resolved_callee {
                    option.some(_) : (),
                    option.none : errors = 1,
                }
            }
            errors = errors + verify_expr_resolved_calls(v.callee.value)
            i := 0
            for i < len(v.args) {
                errors = errors + verify_expr_resolved_calls(v.args[i])
                i = i + 1
            }
            errors
        }
        expr.binary(v) : verify_expr_resolved_calls(v.left.value) + verify_expr_resolved_calls(v.right.value),
        expr.borrow(v) : verify_expr_resolved_calls(v.target.value),
        expr.member(v) : verify_expr_resolved_calls(v.target.value),
        expr.index(v) : verify_expr_resolved_calls(v.target.value) + verify_expr_resolved_calls(v.index.value),
        expr.if(v) : {
            errors := verify_expr_resolved_calls(v.condition.value) + verify_block_resolved_calls(v.then_branch)
            switch v.else_branch {
                option.some(e) : errors = errors + verify_expr_resolved_calls(e.value),
                option.none : (),
            }
            errors
        }
        expr.for(v) : {
            errors := 0
            switch v.init {
                option.some(s) : errors = errors + verify_stmt_resolved_calls(s.value),
                option.none : (),
            }
            switch v.condition {
                option.some(e) : errors = errors + verify_expr_resolved_calls(e.value),
                option.none : (),
            }
            switch v.post {
                option.some(s) : errors = errors + verify_stmt_resolved_calls(s.value),
                option.none : (),
            }
            switch v.iterable {
                option.some(e) : errors = errors + verify_expr_resolved_calls(e.value),
                option.none : (),
            }
            errors + verify_block_resolved_calls(v.body)
        }
        expr.block(v) : verify_block_resolved_calls(v),
        expr.switch(v) : {
            errors := verify_expr_resolved_calls(v.subject.value)
            i := 0
            for i < len(v.arms) {
                errors = errors + verify_expr_resolved_calls(v.arms[i].expr)
                i = i + 1
            }
            errors
        }
        expr.array(v) : {
            errors := 0
            i := 0
            for i < len(v.items) {
                errors = errors + verify_expr_resolved_calls(v.items[i])
                i = i + 1
            }
            errors
        }
        expr.map(v) : {
            errors := 0
            i := 0
            for i < len(v.entries) {
                errors = errors + verify_expr_resolved_calls(v.entries[i].key)
                errors = errors + verify_expr_resolved_calls(v.entries[i].value)
                i = i + 1
            }
            errors
        }
        _ : 0,
    }
}

func mono_item_is_concrete(item value, source_file file) bool {
    switch value {
        item.function(v): len(v.sig.generics) == 0,
        item.method(v): len(v.method.sig.generics) == 0 && !mono_receiver_has_parameter(v.receiver_type, file),
        _: true,
    }
}
func mono_receiver_has_parameter(string receiver, source_file file) bool {
    args := compile.internal.typesys.extract_type_args(receiver)
    base := compile.internal.typesys.base_type_name(receiver)
    i := 0
    for i < len(file.items) {
        name := te_decl_name(file.items[i])
        if name != "" && (base == name || base == te_package(file, i) + "." + name) {
            names := generic_names_from_sig(te_generics(file.items[i])); ai := 0
            for ai < len(args) { ni := 0; for ni < len(names) { if contains_generic_atom(args[ai], names[ni]) { return true }
 ni = ni + 1 }
 ai = ai + 1 }
            return false
        }
        i = i + 1
    }
    i = 0
    for i < len(args) { if looks_like_generic_residue(args[i]) { return true }
 i = i + 1 }
    false
}

func mono_generic_identity(string identity) string {
    i := 0
    for i + 6 <= len(identity) { if prelude_slice(identity, i, i+6) == "__mono" { return prelude_slice(identity, 0, i) }
 i = i + 1 }
    identity
}
func mono_find_work_index(mono_context ctx, string name, string receiver) int {
    found := -1; i := 0
    for i < len(ctx.input_names) {
        candidate_name := ctx.input_names[i]
        candidate_receiver := ctx.input_receivers[i]
        if (receiver == "" && candidate_receiver != "") || (receiver != "" && candidate_receiver == "") { candidate_name = "" }
        pkg := ctx.input_packages[i]
        owner_matches := receiver == "" || compile.internal.typesys.base_type_name(receiver) == compile.internal.typesys.base_type_name(candidate_receiver)
        if candidate_name != "" && owner_matches {
            if name == pkg + "." + candidate_name || (name == candidate_name && pkg == ctx.current_package) { return i }
            if name == candidate_name { if found >= 0 { found = -2 } else if found == -1 { found = i } }
        }
        i = i + 1
    }
    found
}

func mono_substitute_identity(string identity, string[] keys, string[] replacements) string {
    dot := -1; i := 0; depth := 0
    for i < len(identity) { ch := std.prelude.char_at(identity, i); if ch == "[" { depth = depth + 1 }
 if ch == "]" { depth = depth - 1 }
 if ch == "." && depth == 0 { dot = i }
 i = i + 1 }
    if dot < 0 { return identity }
    return substitute_type(prelude_slice(identity, 0, dot), keys, replacements) + prelude_slice(identity, dot, len(identity))
}
func mono_expression_type(expr value) string {
    ty := no_mono_type()
    switch value {
        expr.int(v): ty = v.inferred_type,
        expr.string(v): ty = v.inferred_type,
        expr.bool(v): ty = v.inferred_type,
        expr.name(v): ty = v.inferred_type,
        expr.borrow(v): ty = v.inferred_type,
        expr.binary(v): ty = v.inferred_type,
        expr.member(v): ty = v.inferred_type,
        expr.index(v): ty = v.inferred_type,
        expr.call(v): ty = v.inferred_type,
        expr.record(v): ty = v.inferred_type,
        expr.tuple(v): ty = v.inferred_type,
        expr.switch(v): ty = v.inferred_type,
        expr.if(v): ty = v.inferred_type,
        expr.for(v): ty = v.inferred_type,
        expr.while(v): ty = v.inferred_type,
        expr.block(v): ty = v.inferred_type,
        expr.array(v): ty = v.type_text,
        expr.map(v): ty = v.type_text,
    }
    switch ty { option.some(t): t, option.none: "" }
}

func no_mono_type() option[string] { option.none }

func mono_contains_text(string text, string needle) bool {
    i := 0
    for i + len(needle) <= len(text) {
        if prelude_slice(text, i, i + len(needle)) == needle { return true }
        i = i + 1
    }
    return false
}
