package compile.internal.no_gc_memory

import (
    "compile.internal.drop_flag"
    "compile.internal.drop_system"
    "compile.internal.lifetime_check"
)

func alloc_stack() int { 1 }

func alloc_heap() int { 2 }

struct allocation_decision {
    int strategy
    int size
    string reason
}

struct raii_scope {
    string[] vars
    string[] types
}

struct no_gc_state {
    registry dtor_registry
    flags dflag_map
    lifetimes lifetime_context
}

struct no_gc_result {
    bool ok
    string message
    string[] cleanup
}

func no_gc_state_new() no_gc_state {
    no_gc_state {
        registry: compile.internal.drop_system.dtor_registry_new(),
        flags: compile.internal.drop_flag.drop_flag_new(),
        lifetimes: compile.internal.lifetime_check.lifetime_context_new(),
    }
}

func no_gc_register_drop(no_gc_state state, string type_name, string function_name) no_gc_state {
    impl := compile.internal.drop_system.dtor_impl_new(type_name, true, function_name)
    state.registry = compile.internal.drop_system.dtor_registry_register(state.registry, impl)
    state
}

func no_gc_declare(no_gc_state state, string name, string type_name) no_gc_state {
    state.flags = compile.internal.drop_flag.drop_flag_declare(state.flags, name, type_name)
    state
}

func no_gc_move(no_gc_state state, string from_name, string to_name) no_gc_state {
    state.flags = compile.internal.drop_flag.drop_flag_move(state.flags, from_name, to_name)
    state
}

func no_gc_use(no_gc_state state, string name) no_gc_state {
    state.flags = compile.internal.drop_flag.drop_flag_use(state.flags, name)
    state
}

func no_gc_drop(no_gc_state state, string name) no_gc_state {
    state.flags = compile.internal.drop_flag.drop_flag_drop(state.flags, name)
    state
}

func no_gc_borrow(no_gc_state state, string ref_name, string owner_scope, string ref_scope, bool mutable) no_gc_state {
    state.lifetimes = compile.internal.lifetime_check.lifetime_create_borrow(state.lifetimes, ref_name, owner_scope, ref_scope, mutable)
    state
}

func no_gc_check_dropck(no_gc_state state, string type_name, dropck_field[] fields) lifetime_result {
    compile.internal.lifetime_check.dropck_check_fields(type_name, fields)
}

func no_gc_finish(no_gc_state state) no_gc_result {
    cleanup := compile.internal.drop_flag.drop_flag_cleanup_names(state.flags, state.registry)
    lifetime := compile.internal.lifetime_check.lifetime_finish(state.lifetimes)
    message := ""
    i := 0
    for i < len(state.flags.errors) {
        message = message + state.flags.errors[i] + ";"
        i = i + 1
    }
    if !lifetime.ok { message = message + lifetime.message }
    no_gc_result { ok: len(state.flags.errors) == 0 && lifetime.ok, message: message, cleanup: cleanup }
}

func raii_scope_new() raii_scope {
    string[] vars
    string[] types
    raii_scope { vars: vars, types: types }
}

func raii_track(raii_scope scope, string name, string type_name) raii_scope {
    scope.vars = append(scope.vars, name)
    scope.types = append(scope.types, type_name)
    scope
}

func raii_cleanup(raii_scope scope, dtor_registry registry) string[] {
    cleanup := string[]()
    i := len(scope.vars) - 1
    for i >= 0 {
        if i < len(scope.types) && compile.internal.drop_system.dtor_registry_needs_drop(registry, scope.types[i]) {
            cleanup = append(cleanup, scope.vars[i])
        }
        i = i - 1
    }
    cleanup
}

func decide_allocation_strategy(int type_size, bool dynamic_size) allocation_decision {
    if dynamic_size {
        return allocation_decision { strategy: alloc_heap(), size: type_size, reason: "dynamic size" }
    }
    if type_size <= 4096 {
        return allocation_decision { strategy: alloc_stack(), size: type_size, reason: "fits stack threshold" }
    }
    allocation_decision { strategy: alloc_heap(), size: type_size, reason: "large value" }
}
