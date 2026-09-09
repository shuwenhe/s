package compile.internal.no_gc_test

use compile.internal.drop_flag.drop_flag_cleanup_names
use compile.internal.drop_flag.drop_flag_declare
use compile.internal.drop_flag.drop_flag_drop
use compile.internal.drop_flag.drop_flag_move
use compile.internal.drop_flag.drop_flag_new
use compile.internal.drop_flag.drop_flag_use
use compile.internal.drop_system.check_field_move
use compile.internal.drop_system.dtor_impl_add_field
use compile.internal.drop_system.dtor_impl_new
use compile.internal.drop_system.dtor_registry_new
use compile.internal.drop_system.dtor_registry_register
use compile.internal.drop_system.emit_drop_call
use compile.internal.lifetime_check.dropck_check_fields
use compile.internal.lifetime_check.dropck_field
use compile.internal.lifetime_check.lifetime_context_new
use compile.internal.lifetime_check.lifetime_create_borrow
use compile.internal.lifetime_check.lifetime_enter_scope
use compile.internal.lifetime_check.lifetime_finish
use compile.internal.lifetime_check.lifetime_use_ref
use compile.internal.no_gc_memory.alloc_heap
use compile.internal.no_gc_memory.alloc_stack
use compile.internal.no_gc_memory.decide_allocation_strategy
use compile.internal.no_gc_memory.no_gc_declare
use compile.internal.no_gc_memory.no_gc_finish
use compile.internal.no_gc_memory.no_gc_move
use compile.internal.no_gc_memory.no_gc_register_drop
use compile.internal.no_gc_memory.no_gc_state_new

func run_drop_trait_test() int {
    registry := dtor_registry_new()
    impl := dtor_impl_new("File", true, "__s_drop_File")
    impl = dtor_impl_add_field(impl, "name", "string")
    registry = dtor_registry_register(registry, impl)
    if emit_drop_call(registry, "file", "File") != "__s_drop_File(&file)" { return 1 }
    move_check := check_field_move(registry, "File", "name")
    if move_check.ok { return 2 }
    0
}

func run_drop_flag_test() int {
    registry := dtor_registry_new()
    registry = dtor_registry_register(registry, dtor_impl_new("File", true, "__s_drop_File"))
    flags := drop_flag_new()
    flags = drop_flag_declare(flags, "a", "File")
    flags = drop_flag_move(flags, "a", "b")
    flags = drop_flag_use(flags, "a")
    if len(flags.errors) == 0 { return 1 }

    flags2 := drop_flag_new()
    flags2 = drop_flag_declare(flags2, "x", "File")
    flags2 = drop_flag_drop(flags2, "x")
    flags2 = drop_flag_drop(flags2, "x")
    if len(flags2.errors) == 0 { return 2 }

    flags3 := drop_flag_new()
    flags3 = drop_flag_declare(flags3, "left", "File")
    flags3 = drop_flag_declare(flags3, "right", "File")
    flags3 = drop_flag_move(flags3, "left", "moved")
    cleanup := drop_flag_cleanup_names(flags3, registry)
    if len(cleanup) != 2 || cleanup[0] != "moved" || cleanup[1] != "right" { return 3 }
    0
}

func run_lifetime_test() int {
    ctx := lifetime_context_new()
    ctx = lifetime_enter_scope(ctx, "outer")
    ctx = lifetime_enter_scope(ctx, "inner")
    ctx = lifetime_create_borrow(ctx, "r", "outer", "inner", false)
    ctx = lifetime_use_ref(ctx, "r")
    if !lifetime_finish(ctx).ok { return 1 }

    bad := lifetime_context_new()
    bad = lifetime_enter_scope(bad, "outer")
    bad = lifetime_enter_scope(bad, "inner")
    bad = lifetime_create_borrow(bad, "dangling", "inner", "outer", false)
    if lifetime_finish(bad).ok { return 2 }

    dropck_field[] fields
    fields = append(fields, dropck_field { name: "ref_field", lifetime_name: "", accessed_by_drop: true })
    if dropck_check_fields("Wrapper", fields).ok { return 3 }
    0
}

func run_no_gc_memory_test() int {
    state := no_gc_state_new()
    state = no_gc_register_drop(state, "File", "__s_drop_File")
    state = no_gc_declare(state, "source", "File")
    state = no_gc_move(state, "source", "target")
    result := no_gc_finish(state)
    if !result.ok || len(result.cleanup) != 1 || result.cleanup[0] != "target" { return 1 }

    stack := decide_allocation_strategy(64, false)
    if stack.strategy != alloc_stack() { return 2 }
    heap := decide_allocation_strategy(8192, false)
    if heap.strategy != alloc_heap() { return 3 }
    dynamic := decide_allocation_strategy(8, true)
    if dynamic.strategy != alloc_heap() { return 4 }
    0
}

func run_no_gc_tests() int {
    if run_drop_trait_test() != 0 { return 1 }
    if run_drop_flag_test() != 0 { return 2 }
    if run_lifetime_test() != 0 { return 3 }
    if run_no_gc_memory_test() != 0 { return 4 }
    0
}
