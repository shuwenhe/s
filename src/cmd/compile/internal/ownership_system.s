package compile.internal.ownership_system

use compile.internal.borrow.borrow_check_events
use compile.internal.borrow.lifetime_check_events as trace_lifetime_check_events
use compile.internal.borrow.ownership_check_events as trace_ownership_check_events
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
use compile.internal.no_gc_memory.no_gc_declare
use compile.internal.no_gc_memory.no_gc_finish
use compile.internal.no_gc_memory.no_gc_move
use compile.internal.no_gc_memory.no_gc_register_drop
use compile.internal.no_gc_memory.no_gc_state_new

func ownership_system_verify() int {
    if verify_ownership_and_move() != 0 { return 1 }
    if verify_borrow_rules() != 0 { return 2 }
    if verify_drop_flags_and_destructors() != 0 { return 3 }
    if verify_lifetime_rules() != 0 { return 4 }
    if verify_no_gc_compiler_state() != 0 { return 5 }
    0
}

func verify_ownership_and_move() int {
    ok_events := vec[string]()
    ok_events = append(ok_events, "declare:copy_value:copy")
    ok_events = append(ok_events, "copy:copy_value")
    ok_events = append(ok_events, "use:copy_value")
    ok_events = append(ok_events, "declare:owner:move")
    ok_events = append(ok_events, "move:owner")
    ok := trace_ownership_check_events(ok_events)
    if !ok.ok { return 1 }

    bad_events := vec[string]()
    bad_events = append(bad_events, "declare:owner:move")
    bad_events = append(bad_events, "move:owner")
    bad_events = append(bad_events, "use:owner")
    bad := trace_ownership_check_events(bad_events)
    if bad.ok { return 2 }
    0
}

func verify_borrow_rules() int {
    shared_ok := vec[string]()
    shared_ok = append(shared_ok, "declare:value")
    shared_ok = append(shared_ok, "shared:value")
    shared_ok = append(shared_ok, "read:value")
    shared_ok = append(shared_ok, "end_shared:value")
    ok := borrow_check_events(shared_ok)
    if !ok.ok { return 1 }

    shared_then_mut := vec[string]()
    shared_then_mut = append(shared_then_mut, "declare:value")
    shared_then_mut = append(shared_then_mut, "shared:value")
    shared_then_mut = append(shared_then_mut, "mutable:value")
    bad := borrow_check_events(shared_then_mut)
    if bad.ok { return 2 }

    move_while_borrowed := vec[string]()
    move_while_borrowed = append(move_while_borrowed, "declare:value")
    move_while_borrowed = append(move_while_borrowed, "mutable:value")
    move_while_borrowed = append(move_while_borrowed, "move:value")
    bad_move := borrow_check_events(move_while_borrowed)
    if bad_move.ok { return 3 }
    0
}

func verify_drop_flags_and_destructors() int {
    registry := dtor_registry_new()
    file_impl := dtor_impl_new("File", true, "__s_drop_File")
    file_impl = dtor_impl_add_field(file_impl, "name", "string")
    registry = dtor_registry_register(registry, file_impl)
    if emit_drop_call(registry, "file", "File") != "__s_drop_File(&file)" { return 1 }
    if check_field_move(registry, "File", "name").ok { return 2 }

    flags := drop_flag_new()
    flags = drop_flag_declare(flags, "a", "File")
    flags = drop_flag_move(flags, "a", "b")
    flags = drop_flag_use(flags, "a")
    if len(flags.errors) == 0 { return 3 }

    flags2 := drop_flag_new()
    flags2 = drop_flag_declare(flags2, "x", "File")
    flags2 = drop_flag_drop(flags2, "x")
    flags2 = drop_flag_drop(flags2, "x")
    if len(flags2.errors) == 0 { return 4 }

    flags3 := drop_flag_new()
    flags3 = drop_flag_declare(flags3, "left", "File")
    flags3 = drop_flag_declare(flags3, "right", "File")
    flags3 = drop_flag_move(flags3, "left", "moved")
    cleanup := drop_flag_cleanup_names(flags3, registry)
    if len(cleanup) != 2 || cleanup[0] != "moved" || cleanup[1] != "right" { return 5 }
    0
}

func verify_lifetime_rules() int {
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

    trace_bad := vec[string]()
    trace_bad = append(trace_bad, "scope:outer")
    trace_bad = append(trace_bad, "scope:inner")
    trace_bad = append(trace_bad, "borrow:r:inner:outer")
    if trace_lifetime_check_events(trace_bad).ok { return 3 }

    fields := vec[dropck_field]()
    fields = append(fields, dropck_field { name: "ref_field", lifetime_name: "", accessed_by_drop: true })
    if dropck_check_fields("Wrapper", fields).ok { return 4 }
    0
}

func verify_no_gc_compiler_state() int {
    state := no_gc_state_new()
    state = no_gc_register_drop(state, "File", "__s_drop_File")
    state = no_gc_declare(state, "source", "File")
    state = no_gc_move(state, "source", "target")
    result := no_gc_finish(state)
    if !result.ok { return 1 }
    if len(result.cleanup) != 1 || result.cleanup[0] != "target" { return 2 }
    0
}
