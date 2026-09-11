package compile.internal.mono
use compile.internal.typesys.is_copy_type
use compile.internal.typesys.ownership_mode
use compile.internal.typesys.base_type_name
use compile.internal.typesys.extract_type_args
use compile.internal.typesys.parse_type
use compile.internal.typesys.requires_drop
use std.prelude.box
use s.function_decl
use s.function_sig
use s.param
use s.source_file
use s.item
use s.block_expr
use s.expr
use s.stmt
use s.var_stmt
use s.assign_stmt
use s.increment_stmt
use s.c_for_stmt
use s.return_stmt
use s.expr_stmt
use s.defer_stmt
use s.sroutine_stmt
use s.borrow_expr
use s.binary_expr
use s.member_expr
use s.index_expr
use s.call_expr
use s.if_expr
use s.for_expr
use s.switch_expr
use s.switch_arm
use s.array_literal
use s.map_literal
use s.map_entry
use std.option.option

struct generic_instance_key {
    string function_name
    string[] type_args
}

struct mono_instance {
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
    source_file file
    mono_cache cache
    int invariant_errors
}

struct mono_work_item {
    string generic_name
    string[] type_args
}

// MonoContext: the unified context for monomorphization processing
// - cache: tracks all (generic_def, type_args) -> instance_name mappings
// - worklist: pending (generic_name, type_args) pairs to process
// - processed: set of processed work items, keyed by "name:type_args"
// - generated: all generated concrete function instances
struct mono_context {
    mono_cache cache
    mono_work_item[] worklist
    string[] processed
    function_decl[] generated
}

func new_context() mono_context {
    mono_context {
        cache: new_cache(),
        worklist: mono_work_item[] {},
        processed: string[] {},
        generated: function_decl[] {},
    }
}

func mono_work_key(string generic_name, string[] type_args) string {
    key := generic_name
    i := 0
    for i < len(type_args) {
        key = key + ":" + type_args[i]
        i = i + 1
    }
    key
}

func is_work_processed(mono_context ctx, string generic_name, string[] type_args) bool {
    key := mono_work_key(generic_name, type_args)
    i := 0
    for i < len(ctx.processed) {
        if ctx.processed[i] == key {
            return true
        }
        i = i + 1
    }
    false
}

func mark_work_processed(mono_context ctx, string generic_name, string[] type_args) mono_context {
    key := mono_work_key(generic_name, type_args)
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
        ch := string(type_name[i])
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

func same_type_args(string[] left, string[] right) bool {
    if len(left) != len(right) { return false }
    i := 0
    for i < len(left) {
        if left[i] != right[i] { return false }
        i = i + 1
    }
    true
}

func mono_cache_lookup(mono_cache cache, string generic_name, string[] type_args) string {
    i := 0
    for i < len(cache.instances) {
        instance := cache.instances[i]
        if instance.generic_name == generic_name && same_type_args(instance.type_args, type_args) {
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
    existing := mono_cache_lookup(cache, generic_name, type_args)
    if existing != "" { return mono_cache_result { cache: cache, instance_name: existing } }
    name := make_instance_name(generic_name, type_args)
    cache.instances = append(cache.instances, mono_instance {
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

func monomorphize_file(source_file file) monomorphize_file_result {
    // Initialize monomorphization context
    ctx := new_context()
    extra_items := item[]()
    
    // Phase 1: Collect seed instances from all top-level items
    // This identifies all monomorphization requests (generic calls with concrete type arguments)
    i := 0
    for i < len(file.items) {
        ctx = collect_item_instances_ctx(file.items[i], file.items, ctx)
        i = i + 1
    }
    
    // Phase 2: Process worklist with transitive closure (worklist algorithm)
    // This ensures we generate all transitively required instances
    // Example: foo[int] calls bar[int], which calls baz[int] - all three get generated
    cursor := 0
    for cursor < len(ctx.worklist) {
        work := ctx.worklist[cursor]
        cursor = cursor + 1
        
        // Skip if already processed (handles cycles and duplicates)
        if is_work_processed(ctx, work.generic_name, work.type_args) {
            continue
        }
        ctx = mark_work_processed(ctx, work.generic_name, work.type_args)
        
        // Find generic source definition in the file
        source := find_generic_function(file.items, work.generic_name)
        if source.sig.name == "" {
            continue
        }
        
        // Specialize the generic function with concrete type arguments
        instance := specialize_function(source, work.type_args)
        ctx.generated = append(ctx.generated, instance)
        
        // Collect instances called by this specialized function (transitive discovery)
        // This may add new work items to the worklist
        ctx = collect_item_instances_ctx(item::function(instance), file.items, ctx)
        
        // Finalize and add to output
        extra_items = append(extra_items, item::function(finalize_monomorphized_function(instance)))
    }
    
    // Phase 3: Remove all generic functions from original file
    // Keep only concrete functions and non-function items
    stripped := item[]()
    i = 0
    for i < len(file.items) {
        if should_keep_after_monomorphization(file.items[i]) {
            stripped = append(stripped, file.items[i])
        }
        i = i + 1
    }
    file.items = stripped
    
    // Phase 4: Add all generated monomorphic instances
    i = 0
    for i < len(extra_items) {
        file.items = append(file.items, extra_items[i])
        i = i + 1
    }
    
    monomorphize_file_result { file: file, cache: ctx.cache, invariant_errors: verify_monomorphized_file(file) }
}

func should_keep_after_monomorphization(item value) bool {
    switch value {
        item.function(fn) : len(fn.sig.generics) == 0,
        item.method(method) : len(method.method.sig.generics) == 0,
        _ : true,
    }
}

// collect_item_instances_ctx: collect monomorphization instances using MonoContext
func collect_item_instances_ctx(item value, item[] all_items, mono_context ctx) mono_context {
    switch value {
        item.function(fn) : {
            switch fn.body {
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
    i := 0
    for i < len(block.statements) {
        ctx = collect_stmt_instances_ctx(block.statements[i], all_items, ctx)
        i = i + 1
    }
    switch block.final_expr {
        option.some(value) : ctx = collect_expr_instances_ctx(value, all_items, ctx),
        option.none : (),
    }
    ctx
}

func collect_stmt_instances_ctx(stmt value, item[] all_items, mono_context ctx) mono_context {
    switch value {
        stmt.let(v) : collect_expr_instances_ctx(v.value, all_items, ctx),
        stmt.assign(v) : collect_expr_instances_ctx(v.value, all_items, ctx),
        stmt.increment(_) : ctx,
        stmt.c_for(v) : {
            ctx = collect_stmt_instances_ctx(v.init.value, all_items, ctx)
            ctx = collect_expr_instances_ctx(v.condition, all_items, ctx)
            ctx = collect_stmt_instances_ctx(v.step.value, all_items, ctx)
            collect_block_instances_ctx(v.body, all_items, ctx)
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
    switch value {
        expr.borrow(v) : collect_expr_instances_ctx(v.target.value, all_items, ctx),
        expr.binary(v) : {
            ctx = collect_expr_instances_ctx(v.left.value, all_items, ctx)
            collect_expr_instances_ctx(v.right.value, all_items, ctx)
        }
        expr.member(v) : collect_expr_instances_ctx(v.target.value, all_items, ctx),
        expr.index(v) : {
            ctx = collect_expr_instances_ctx(v.target.value, all_items, ctx)
            collect_expr_instances_ctx(v.index.value, all_items, ctx)
        }
        expr.call(v) : {
            ctx = collect_call_instance_ctx(v, all_items, ctx)
            i := 0
            for i < len(v.args) {
                ctx = collect_expr_instances_ctx(v.args[i], all_items, ctx)
                i = i + 1
            }
            collect_expr_instances_ctx(v.callee.value, all_items, ctx)
        }
        expr.if(v) : {
            ctx = collect_expr_instances_ctx(v.condition.value, all_items, ctx)
            ctx = collect_block_instances_ctx(v.then_branch, all_items, ctx)
            switch v.else_branch {
                option.some(e) : collect_expr_instances_ctx(e.value, all_items, ctx),
                option.none : ctx,
            }
        }
        expr.for(v) : collect_for_instances_ctx(v, all_items, ctx),
        expr.block(v) : collect_block_instances_ctx(v, all_items, ctx),
        expr.switch(v) : {
            ctx = collect_expr_instances_ctx(v.subject.value, all_items, ctx)
            i := 0
            for i < len(v.arms) {
                ctx = collect_expr_instances_ctx(v.arms[i].expr, all_items, ctx)
                i = i + 1
            }
            ctx
        }
        expr.array(v) : {
            i := 0
            for i < len(v.items) {
                ctx = collect_expr_instances_ctx(v.items[i], all_items, ctx)
                i = i + 1
            }
            ctx
        }
        expr.map(v) : {
            i := 0
            for i < len(v.entries) {
                ctx = collect_expr_instances_ctx(v.entries[i].key, all_items, ctx)
                ctx = collect_expr_instances_ctx(v.entries[i].value, all_items, ctx)
                i = i + 1
            }
            ctx
        }
        _ : ctx,
    }
}

func collect_call_instance_ctx(call_expr call, item[] all_items, mono_context ctx) mono_context {
    if len(call.type_args) == 0 {
        return ctx
    }
    
    resolved := ""
    switch call.resolved_callee {
        option.some(name) : resolved = name,
        option.none : return ctx,
    }
    
    generic_name := ""
    switch call.callee.value {
        expr.name(name) : generic_name = name.name,
        _ : return ctx,
    }
    
    source := find_generic_function(all_items, generic_name)
    if source.sig.name == "" {
        return ctx
    }
    
    // Check if this instance already exists
    existing := mono_cache_lookup(ctx.cache, generic_name, call.type_args)
    result := mono_cache_get_or_create(ctx.cache, generic_name, call.type_args)
    ctx.cache = result.cache
    
    // If this is a new instance, add it to worklist for processing
    if existing == "" {
        ctx.worklist = append(ctx.worklist, mono_work_item { generic_name: generic_name, type_args: call.type_args })
    }
    
    ctx
}

func collect_for_instances_ctx(for_expr v, item[] all_items, mono_context ctx) mono_context {
    switch v.init {
        option.some(s) : ctx = collect_stmt_instances_ctx(s.value, all_items, ctx),
        option.none : (),
    }
    switch v.condition {
        option.some(e) : ctx = collect_expr_instances_ctx(e.value, all_items, ctx),
        option.none : (),
    }
    switch v.post {
        option.some(s) : ctx = collect_stmt_instances_ctx(s.value, all_items, ctx),
        option.none : (),
    }
    switch v.iterable {
        option.some(e) : ctx = collect_expr_instances_ctx(e.value, all_items, ctx),
        option.none : (),
    }
    collect_block_instances_ctx(v.body, all_items, ctx)
}

func collect_item_instances(item value, item[] all_items, mono_cache cache, mono_work_item[] worklist) mono_cache {
    switch value {
        item.function(fn) : {
            switch fn.body {
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
    i := 0
    for i < len(block.statements) {
        cache = collect_stmt_instances(block.statements[i], all_items, cache, worklist)
        i = i + 1
    }
    switch block.final_expr {
        option.some(value) : cache = collect_expr_instances(value, all_items, cache, worklist),
        option.none : (),
    }
    cache
}

func collect_stmt_instances(stmt value, item[] all_items, mono_cache cache, mono_work_item[] worklist) mono_cache {
    switch value {
        stmt.let(v) : collect_expr_instances(v.value, all_items, cache, worklist),
        stmt.assign(v) : collect_expr_instances(v.value, all_items, cache, worklist),
        stmt.increment(_) : cache,
        stmt.c_for(v) : {
            cache = collect_stmt_instances(v.init.value, all_items, cache, worklist)
            cache = collect_expr_instances(v.condition, all_items, cache, worklist)
            cache = collect_stmt_instances(v.step.value, all_items, cache, worklist)
            collect_block_instances(v.body, all_items, cache, worklist)
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
    switch value {
        expr.borrow(v) : collect_expr_instances(v.target.value, all_items, cache, worklist),
        expr.binary(v) : {
            cache = collect_expr_instances(v.left.value, all_items, cache, worklist)
            collect_expr_instances(v.right.value, all_items, cache, worklist)
        }
        expr.member(v) : collect_expr_instances(v.target.value, all_items, cache, worklist),
        expr.index(v) : {
            cache = collect_expr_instances(v.target.value, all_items, cache, worklist)
            collect_expr_instances(v.index.value, all_items, cache, worklist)
        }
        expr.call(v) : {
            cache = collect_call_instance(v, all_items, cache, worklist)
            i := 0
            for i < len(v.args) {
                cache = collect_expr_instances(v.args[i], all_items, cache, worklist)
                i = i + 1
            }
            collect_expr_instances(v.callee.value, all_items, cache, worklist)
        }
        expr.if(v) : {
            cache = collect_expr_instances(v.condition.value, all_items, cache, worklist)
            cache = collect_block_instances(v.then_branch, all_items, cache, worklist)
            switch v.else_branch {
                option.some(e) : collect_expr_instances(e.value, all_items, cache, worklist),
                option.none : cache,
            }
        }
        expr.for(v) : collect_for_instances(v, all_items, cache, worklist),
        expr.block(v) : collect_block_instances(v, all_items, cache, worklist),
        expr.switch(v) : {
            cache = collect_expr_instances(v.subject.value, all_items, cache, worklist)
            i := 0
            for i < len(v.arms) {
                cache = collect_expr_instances(v.arms[i].expr, all_items, cache, worklist)
                i = i + 1
            }
            cache
        }
        expr.array(v) : {
            i := 0
            for i < len(v.items) {
                cache = collect_expr_instances(v.items[i], all_items, cache, worklist)
                i = i + 1
            }
            cache
        }
        expr.map(v) : {
            i := 0
            for i < len(v.entries) {
                cache = collect_expr_instances(v.entries[i].key, all_items, cache, worklist)
                cache = collect_expr_instances(v.entries[i].value, all_items, cache, worklist)
                i = i + 1
            }
            cache
        }
        _ : cache,
    }
}

func collect_call_instance(call_expr call, item[] all_items, mono_cache cache, mono_work_item[] worklist) mono_cache {
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
    existing := mono_cache_lookup(cache, generic_name, call.type_args)
    result := mono_cache_get_or_create(cache, generic_name, call.type_args)
    cache = result.cache
    if existing == "" && result.instance_name == resolved {
        worklist = append(worklist, mono_work_item { generic_name: generic_name, type_args call.type_args })
    }
    cache
}

func collect_for_instances(for_expr v, item[] all_items, mono_cache cache, mono_work_item[] worklist) mono_cache {
    switch v.init {
        option.some(s) : cache = collect_stmt_instances(s.value, all_items, cache, worklist),
        option.none : (),
    }
    switch v.condition {
        option.some(e) : cache = collect_expr_instances(e.value, all_items, cache, worklist),
        option.none : (),
    }
    switch v.post {
        option.some(s) : cache = collect_stmt_instances(s.value, all_items, cache, worklist),
        option.none : (),
    }
    switch v.iterable {
        option.some(e) : cache = collect_expr_instances(e.value, all_items, cache, worklist),
        option.none : (),
    }
    collect_block_instances(v.body, all_items, cache, worklist)
}

func find_generic_function(item[] items, string name) function_decl {
    i := 0
    for i < len(items) {
        switch items[i] {
            item.function(fn) : {
                if fn.sig.name == name && len(fn.sig.generics) > 0 {
                    return fn
                }
            }
            _ : (),
        }
        i = i + 1
    }
    function_decl empty
    empty
}

func verify_monomorphized_file(source_file file) int {
    errors := 0
    i := 0
    for i < len(file.items) {
        switch file.items[i] {
            item.function(fn) : {
                if len(fn.sig.generics) == 0 && contains_text(fn.sig.name, "__mono") {
                    errors = errors + verify_function_no_generics(fn)
                }
            }
            item.method(method) : {
                if len(method.method.sig.generics) == 0 && contains_text(method.method.sig.name, "__mono") {
                    errors = errors + verify_function_no_generics(method.method)
                }
            }
            _ : (),
        }
        i = i + 1
    }
    errors
}

func finalize_monomorphized_function(function_decl fn) function_decl {
    body := option.none
    switch fn.body {
        option.some(value) : body = option.some(finalize_block(value)),
        option.none : (),
    }
    function_decl { sig: fn.sig, body body, is_public fn.is_public }
}

func finalize_block(block_expr block) block_expr {
    stmts := stmt[]()
    i := 0
    for i < len(block.statements) {
        stmts = append(stmts, finalize_stmt(block.statements[i]))
        i = i + 1
    }
    final_expr := option.none
    switch block.final_expr {
        option.some(value) : final_expr = option.some(finalize_expr(value)),
        option.none : (),
    }
    block_expr { statements: stmts, final_expr final_expr, inferred_type block.inferred_type }
}

func finalize_stmt(stmt value) stmt {
    switch value {
        stmt.let(v) : stmt::let(var_stmt { name: v.name, type_name v.type_name, value finalize_expr(v.value) }),
        stmt.assign(v) : stmt::assign(assign_stmt { name: v.name, value finalize_expr(v.value) }),
        stmt.increment(v) : stmt::increment(v),
        stmt.c_for(v) : stmt::c_for(c_for_stmt { init: box(finalize_stmt(v.init.value)), condition finalize_expr(v.condition), step box(finalize_stmt(v.step.value)), body finalize_block(v.body) }),
        stmt.return(v) : {
            ret := option.none
            switch v.value {
                option.some(e) : ret = option.some(finalize_expr(e)),
                option.none : (),
            }
            stmt::return(return_stmt { value: ret })
        }
        stmt.expr(v) : stmt::expr(expr_stmt { expr: finalize_expr(v.expr) }),
        stmt.defer(v) : stmt::defer(defer_stmt { expr: finalize_expr(v.expr) }),
        stmt.sroutine(v) : stmt::sroutine(sroutine_stmt { expr: finalize_expr(v.expr) }),
    }
}

func finalize_expr(expr value) expr {
    switch value {
        expr.int(v) : expr::int(v),
        expr.string(v) : expr::string(v),
        expr.bool(v) : expr::bool(v),
        expr.name(v) : expr::name(v),
        expr.borrow(v) : expr::borrow(borrow_expr { target: box(finalize_expr(v.target.value)), mutable v.mutable, inferred_type v.inferred_type }),
        expr.binary(v) : expr::binary(binary_expr { left: box(finalize_expr(v.left.value)), op v.op, right box(finalize_expr(v.right.value)), inferred_type v.inferred_type }),
        expr.member(v) : expr::member(member_expr { target: box(finalize_expr(v.target.value)), member v.member, inferred_type v.inferred_type }),
        expr.index(v) : expr::index(index_expr { target: box(finalize_expr(v.target.value)), index box(finalize_expr(v.index.value)), inferred_type v.inferred_type }),
        expr.call(v) : {
            args := expr[]()
            i := 0
            for i < len(v.args) {
                args = append(args, finalize_expr(v.args[i]))
                i = i + 1
            }
            expr::call(call_expr { callee: box(finalize_expr(v.callee.value)), args args, inferred_type v.inferred_type, resolved_callee v.resolved_callee, type_args string[]() })
        }
        expr.if(v) : {
            else_branch := option.none
            switch v.else_branch {
                option.some(e) : else_branch = option.some(box(finalize_expr(e.value))),
                option.none : (),
            }
            expr::if(if_expr { condition: box(finalize_expr(v.condition.value)), then_branch finalize_block(v.then_branch), else_branch else_branch, inferred_type v.inferred_type })
        }
        expr.for(v) : finalize_for_expr(v),
        expr.block(v) : expr::block(finalize_block(v)),
        expr.switch(v) : {
            arms := switch_arm[]()
            i := 0
            for i < len(v.arms) {
                arms = append(arms, switch_arm { pattern: v.arms[i].pattern, expr finalize_expr(v.arms[i].expr) })
                i = i + 1
            }
            expr::switch(switch_expr { subject: box(finalize_expr(v.subject.value)), arms arms, inferred_type v.inferred_type })
        }
        expr.array(v) : {
            items := expr[]()
            i := 0
            for i < len(v.items) {
                items = append(items, finalize_expr(v.items[i]))
                i = i + 1
            }
            expr::array(array_literal { type_text: v.type_text, items items })
        }
        expr.map(v) : {
            entries := map_entry[]()
            i := 0
            for i < len(v.entries) {
                entries = append(entries, map_entry { key: finalize_expr(v.entries[i].key), value finalize_expr(v.entries[i].value) })
                i = i + 1
            }
            expr::map(map_literal { type_text: v.type_text, entries entries })
        }
    }
}

func finalize_for_expr(for_expr v) expr {
    init := option.none
    switch v.init {
        option.some(s) : init = option.some(box(finalize_stmt(s.value))),
        option.none : (),
    }
    condition := option.none
    switch v.condition {
        option.some(e) : condition = option.some(box(finalize_expr(e.value))),
        option.none : (),
    }
    post := option.none
    switch v.post {
        option.some(s) : post = option.some(box(finalize_stmt(s.value))),
        option.none : (),
    }
    iterable := option.none
    switch v.iterable {
        option.some(e) : iterable = option.some(box(finalize_expr(e.value))),
        option.none : (),
    }
    expr::for(for_expr { init: init, condition condition, post post, names v.names, iterable iterable, body finalize_block(v.body), inferred_type v.inferred_type })
}

func verify_function_no_generics(function_decl fn) int {
    errors := 0
    i := 0
    for i < len(fn.sig.params) {
        if looks_like_generic_residue(fn.sig.params[i].type_name) {
            errors = errors + 1
        }
        i = i + 1
    }
    switch fn.sig.return_type {
        option.some(ty) : {
            if looks_like_generic_residue(ty) {
                errors = errors + 1
            }
        }
        option.none : (),
    }
    switch fn.body {
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
        stmt.let(v) : verify_optional_type_no_generics(v.type_name) + verify_expr_no_generics(v.value),
        stmt.assign(v) : verify_expr_no_generics(v.value),
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

func verify_call_no_generics(call_expr v) int {
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
    clean := parse_type(type_name)
    if clean == "T" || clean == "U" || clean == "V" {
        return true
    }
    contains_generic_atom(clean, "T") || contains_generic_atom(clean, "U") || contains_generic_atom(clean, "V")
}

func contains_generic_atom(string text, string atom) bool {
    i := 0
    for i < len(text) {
        if slice(text, i, i + 1) == atom {
            left_ok := i == 0 || !is_ident_char(slice(text, i - 1, i))
            right_ok := i + 1 >= len(text) || !is_ident_char(slice(text, i + 1, i + 2))
            if left_ok && right_ok {
                return true
            }
        }
        i = i + 1
    }
    false
}

func is_ident_char(string ch) bool {
    (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z") || (ch >= "0" && ch <= "9") || ch == "_"
}

func substitute_type(string type_name, string[] generic_names, string[] type_args) string {
    clean := parse_type(type_name)
    i := 0
    for i < len(generic_names) {
        if clean == generic_names[i] {
            if i < len(type_args) { return type_args[i] }
            return "unknown"
        }
        i = i + 1
    }
    if starts_with(clean, "&mut") {
        return "&mut " + substitute_type(slice(clean, 4, len(clean)), generic_names, type_args)
    }
    if starts_with(clean, "&") {
        return "&" + substitute_type(slice(clean, 1, len(clean)), generic_names, type_args)
    }
    if ends_with(clean, "[]") {
        return substitute_type(slice(clean, 0, len(clean) - 2), generic_names, type_args) + "[]"
    }
    if starts_with(clean, "[]") {
        return "[]" + substitute_type(slice(clean, 2, len(clean)), generic_names, type_args)
    }
    args := extract_type_args(clean)
    if len(args) == 0 {
        return clean
    }
    base := base_type_name(clean)
    built := base + "["
    i = 0
    for i < len(args) {
        if i > 0 {
            built = built + ", "
        }
        built = built + substitute_type(args[i], generic_names, type_args)
        i = i + 1
    }
    built + "]"
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
        if string(text[i]) == needle { return i }
        i = i + 1
    }
    -1
}

func specialize_function(function_decl source, string[] type_args) function_decl {
    generic_names := string[] {}
    i := 0
    for i < len(source.sig.generics) {
        raw := source.sig.generics[i]
        colon := find_char(raw, ":")
        if colon >= 0 { raw = slice(raw, 0, colon) }
        generic_names = append(generic_names, raw)
        i = i + 1
    }
    params := param[] {}
    i = 0
    for i < len(source.sig.params) {
        original := source.sig.params[i]
        params = append(params, param {
            name: original.name,
            type_name: substitute_type(original.type_name, generic_names, type_args),
        })
        i = i + 1
    }
    return_type := substitute_optional_type(source.sig.return_type, generic_names, type_args)
    body := option.none
    switch source.body {
        option.some(value) : body = option.some(substitute_block(value, generic_names, type_args)),
        option.none : (),
    }
    function_decl {
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

func substitute_block(block_expr block, string[] generic_names, string[] type_args) block_expr {
    stmts := stmt[]()
    i := 0
    for i < len(block.statements) {
        stmts = append(stmts, substitute_stmt(block.statements[i], generic_names, type_args))
        i = i + 1
    }
    final_expr := option.none
    switch block.final_expr {
        option.some(value) : final_expr = option.some(substitute_expr(value, generic_names, type_args)),
        option.none : (),
    }
    block_expr { statements: stmts, final_expr final_expr, inferred_type substitute_optional_type(block.inferred_type, generic_names, type_args) }
}

func substitute_stmt(stmt value, string[] generic_names, string[] type_args) stmt {
    switch value {
        stmt.let(v) : stmt::let(var_stmt { name: v.name, type_name substitute_optional_type(v.type_name, generic_names, type_args), value substitute_expr(v.value, generic_names, type_args) }),
        stmt.assign(v) : stmt::assign(assign_stmt { name: v.name, value substitute_expr(v.value, generic_names, type_args) }),
        stmt.increment(v) : stmt::increment(increment_stmt { name: v.name }),
        stmt.c_for(v) : stmt::c_for(c_for_stmt { init: box(substitute_stmt(v.init.value, generic_names, type_args)), condition substitute_expr(v.condition, generic_names, type_args), step box(substitute_stmt(v.step.value, generic_names, type_args)), body substitute_block(v.body, generic_names, type_args) }),
        stmt.return(v) : {
            ret := option.none
            switch v.value {
                option.some(e) : ret = option.some(substitute_expr(e, generic_names, type_args)),
                option.none : (),
            }
            stmt::return(return_stmt { value: ret })
        }
        stmt.expr(v) : stmt::expr(expr_stmt { expr: substitute_expr(v.expr, generic_names, type_args) }),
        stmt.defer(v) : stmt::defer(defer_stmt { expr: substitute_expr(v.expr, generic_names, type_args) }),
        stmt.sroutine(v) : stmt::sroutine(sroutine_stmt { expr: substitute_expr(v.expr, generic_names, type_args) }),
    }
}

func substitute_expr(expr value, string[] generic_names, string[] type_args) expr {
    switch value {
        expr.int(v) : expr::int(v),
        expr.string(v) : expr::string(v),
        expr.bool(v) : expr::bool(v),
        expr.name(v) : expr::name(v),
        expr.borrow(v) : expr::borrow(borrow_expr { target: box(substitute_expr(v.target.value, generic_names, type_args)), mutable v.mutable, inferred_type substitute_optional_type(v.inferred_type, generic_names, type_args) }),
        expr.binary(v) : expr::binary(binary_expr { left: box(substitute_expr(v.left.value, generic_names, type_args)), op v.op, right box(substitute_expr(v.right.value, generic_names, type_args)), inferred_type substitute_optional_type(v.inferred_type, generic_names, type_args) }),
        expr.member(v) : expr::member(member_expr { target: box(substitute_expr(v.target.value, generic_names, type_args)), member v.member, inferred_type substitute_optional_type(v.inferred_type, generic_names, type_args) }),
        expr.index(v) : expr::index(index_expr { target: box(substitute_expr(v.target.value, generic_names, type_args)), index box(substitute_expr(v.index.value, generic_names, type_args)), inferred_type substitute_optional_type(v.inferred_type, generic_names, type_args) }),
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
            switch v.callee.value {
                expr.name(name) : {
                    if len(call_type_args) > 0 {
                        resolved = option.some(make_instance_name(name.name, call_type_args))
                    }
                }
                _ : (),
            }
            expr::call(call_expr { callee: box(substitute_expr(v.callee.value, generic_names, type_args)), args args, inferred_type substitute_optional_type(v.inferred_type, generic_names, type_args), resolved_callee resolved, type_args call_type_args })
        }
        expr.if(v) : {
            else_branch := option.none
            switch v.else_branch {
                option.some(e) : else_branch = option.some(box(substitute_expr(e.value, generic_names, type_args))),
                option.none : (),
            }
            expr::if(if_expr { condition: box(substitute_expr(v.condition.value, generic_names, type_args)), then_branch substitute_block(v.then_branch, generic_names, type_args), else_branch else_branch, inferred_type substitute_optional_type(v.inferred_type, generic_names, type_args) })
        }
        expr.for(v) : substitute_for_expr(v, generic_names, type_args),
        expr.block(v) : expr::block(substitute_block(v, generic_names, type_args)),
        expr.switch(v) : expr::switch(substitute_switch(v, generic_names, type_args)),
        expr.array(v) : substitute_array_expr(v, generic_names, type_args),
        expr.map(v) : substitute_map_expr(v, generic_names, type_args),
    }
}

func substitute_for_expr(for_expr v, string[] generic_names, string[] type_args) expr {
    init := option.none
    switch v.init {
        option.some(s) : init = option.some(box(substitute_stmt(s.value, generic_names, type_args))),
        option.none : (),
    }
    condition := option.none
    switch v.condition {
        option.some(e) : condition = option.some(box(substitute_expr(e.value, generic_names, type_args))),
        option.none : (),
    }
    post := option.none
    switch v.post {
        option.some(s) : post = option.some(box(substitute_stmt(s.value, generic_names, type_args))),
        option.none : (),
    }
    iterable := option.none
    switch v.iterable {
        option.some(e) : iterable = option.some(box(substitute_expr(e.value, generic_names, type_args))),
        option.none : (),
    }
    expr::for(for_expr { init: init, condition condition, post post, names v.names, iterable iterable, body substitute_block(v.body, generic_names, type_args), inferred_type substitute_optional_type(v.inferred_type, generic_names, type_args) })
}

func substitute_switch(switch_expr v, string[] generic_names, string[] type_args) switch_expr {
    arms := switch_arm[]()
    i := 0
    for i < len(v.arms) {
        arms = append(arms, switch_arm { pattern: v.arms[i].pattern, expr substitute_expr(v.arms[i].expr, generic_names, type_args) })
        i = i + 1
    }
    switch_expr { subject: box(substitute_expr(v.subject.value, generic_names, type_args)), arms arms, inferred_type substitute_optional_type(v.inferred_type, generic_names, type_args) }
}

func substitute_array_expr(array_literal v, string[] generic_names, string[] type_args) expr {
    items := expr[]()
    i := 0
    for i < len(v.items) {
        items = append(items, substitute_expr(v.items[i], generic_names, type_args))
        i = i + 1
    }
    expr::array(array_literal { type_text: substitute_optional_type(v.type_text, generic_names, type_args), items items })
}

func substitute_map_expr(map_literal v, string[] generic_names, string[] type_args) expr {
    entries := map_entry[]()
    i := 0
    for i < len(v.entries) {
        entries = append(entries, map_entry { key: substitute_expr(v.entries[i].key, generic_names, type_args), value substitute_expr(v.entries[i].value, generic_names, type_args) })
        i = i + 1
    }
    expr::map(map_literal { type_text: substitute_optional_type(v.type_text, generic_names, type_args), entries entries })
}

func summarize_type(string type_name) mono_ownership_summary {
    mono_ownership_summary {
        type_name: type_name,
        ownership: ownership_mode(type_name),
        copy: is_copy_type(type_name),
        drop: requires_drop(type_name),
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

// verify_monomorphized_file_with_details: verify post-monomorphization invariants with detailed reporting
// Returns number of errors found
// Post-mono invariants:
//   - All concrete functions (__mono) must have no generic type parameters
//   - No residual generics: T, U, V, box[T], T[], etc.
//   - All call expressions must have resolved_callee set
//   - All type_args in calls must be resolved (no T)
func verify_monomorphized_file_with_details(source_file file) int {
    errors := verify_monomorphized_file(file)
    
    // Additional detailed verification for concrete instances
    i := 0
    for i < len(file.items) {
        switch file.items[i] {
            item.function(fn) : {
                if contains_text(fn.sig.name, "__mono") {
                    // Verify call expressions have resolved_callee
                    errors = errors + verify_function_resolved_calls(fn)
                }
            }
            _ : (),
        }
        i = i + 1
    }
    
    errors
}

func verify_function_resolved_calls(function_decl fn) int {
    errors := 0
    switch fn.body {
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
            // Monomorphized calls should have resolved_callee
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
