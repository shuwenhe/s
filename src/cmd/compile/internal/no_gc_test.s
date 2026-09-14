package compile.internal.no_gc_test
import (
    "compile.internal.drop_flag"
    "compile.internal.drop_system"
    "compile.internal.lifetime_check"
    "compile.internal.no_gc_memory"
    "compile.internal.ownership_system"
)
func run_drop_trait_test() int {
    registry := compile.internal.drop_system.dtor_registry_new()
    impl := compile.internal.drop_system.dtor_impl_new("File", true, "__s_drop_File")
    impl = compile.internal.drop_system.dtor_impl_add_field(impl, "name", "string")
    registry = compile.internal.drop_system.dtor_registry_register(registry, impl)
    if compile.internal.drop_system.emit_drop_call(registry, "file", "File") != "__s_drop_File(&file)" { return 1 }
    move_check := compile.internal.drop_system.check_field_move(registry, "File", "name")
    if move_check.ok { return 2 }
    0
}
func run_drop_flag_test() int {
    registry := compile.internal.drop_system.dtor_registry_new()
    registry = compile.internal.drop_system.dtor_registry_register(registry, compile.internal.drop_system.dtor_impl_new("File", true, "__s_drop_File"))
    flags := compile.internal.drop_flag.drop_flag_new()
    flags = compile.internal.drop_flag.drop_flag_declare(flags, "a", "File")
    flags = compile.internal.drop_flag.drop_flag_move(flags, "a", "b")
    flags = compile.internal.drop_flag.drop_flag_use(flags, "a")
    if len(flags.errors) == 0 { return 1 }
    flags2 := compile.internal.drop_flag.drop_flag_new()
    flags2 = compile.internal.drop_flag.drop_flag_declare(flags2, "x", "File")
    flags2 = compile.internal.drop_flag.drop_flag_drop(flags2, "x")
    flags2 = compile.internal.drop_flag.drop_flag_drop(flags2, "x")
    if len(flags2.errors) == 0 { return 2 }
    flags3 := compile.internal.drop_flag.drop_flag_new()
    flags3 = compile.internal.drop_flag.drop_flag_declare(flags3, "left", "File")
    flags3 = compile.internal.drop_flag.drop_flag_declare(flags3, "right", "File")
    flags3 = compile.internal.drop_flag.drop_flag_move(flags3, "left", "moved")
    cleanup := compile.internal.drop_flag.drop_flag_cleanup_names(flags3, registry)
    if len(cleanup) != 2 || cleanup[0] != "moved" || cleanup[1] != "right" { return 3 }
    0
}
func run_lifetime_test() int {
    ctx := compile.internal.lifetime_check.lifetime_context_new()
    ctx = compile.internal.lifetime_check.lifetime_enter_scope(ctx, "outer")
    ctx = compile.internal.lifetime_check.lifetime_enter_scope(ctx, "inner")
    ctx = compile.internal.lifetime_check.lifetime_create_borrow(ctx, "r", "outer", "inner", false)
    ctx = compile.internal.lifetime_check.lifetime_use_ref(ctx, "r")
    if !compile.internal.lifetime_check.lifetime_finish(ctx).ok { return 1 }
    bad := compile.internal.lifetime_check.lifetime_context_new()
    bad = compile.internal.lifetime_check.lifetime_enter_scope(bad, "outer")
    bad = compile.internal.lifetime_check.lifetime_enter_scope(bad, "inner")
    bad = compile.internal.lifetime_check.lifetime_create_borrow(bad, "dangling", "inner", "outer", false)
    if compile.internal.lifetime_check.lifetime_finish(bad).ok { return 2 }
    fields := vec[dropck_field]()
    fields = append(fields, dropck_field { name: "ref_field", lifetime_name: "", accessed_by_drop: true })
    if compile.internal.lifetime_check.dropck_check_fields("Wrapper", fields).ok { return 3 }
    0
}
func run_no_gc_memory_test() int {
    state := compile.internal.no_gc_memory.no_gc_state_new()
    state = compile.internal.no_gc_memory.no_gc_register_drop(state, "File", "__s_drop_File")
    state = compile.internal.no_gc_memory.no_gc_declare(state, "source", "File")
    state = compile.internal.no_gc_memory.no_gc_move(state, "source", "target")
    result := compile.internal.no_gc_memory.no_gc_finish(state)
    if !result.ok || len(result.cleanup) != 1 || result.cleanup[0] != "target" { return 1 }
    stack := compile.internal.no_gc_memory.decide_allocation_strategy(64, false)
    if stack.strategy != compile.internal.no_gc_memory.alloc_stack() { return 2 }
    heap := compile.internal.no_gc_memory.decide_allocation_strategy(8192, false)
    if heap.strategy != compile.internal.no_gc_memory.alloc_heap() { return 3 }
    dynamic := compile.internal.no_gc_memory.decide_allocation_strategy(8, true)
    if dynamic.strategy != compile.internal.no_gc_memory.alloc_heap() { return 4 }
    0
}
func run_no_gc_tests() int {
    if compile.internal.ownership_system.ownership_system_verify() != 0 { return 5 }
    if run_drop_trait_test() != 0 { return 1 }
    if run_drop_flag_test() != 0 { return 2 }
    if run_lifetime_test() != 0 { return 3 }
    if run_no_gc_memory_test() != 0 { return 4 }
    0
