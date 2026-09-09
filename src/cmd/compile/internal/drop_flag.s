package compile.internal.drop_flag

use compile.internal.drop_system.dtor_registry
use compile.internal.drop_system.dtor_registry_needs_drop
use compile.internal.drop_system.emit_drop_call

func drop_state_unknown() int { 0 }
func drop_state_present() int { 1 }
func drop_state_absent() int { 2 }
func drop_state_partial() int { 3 }

struct dflag_entry {
    string name
    string type_name
    int state
    int scope_depth
}

struct dflag_map {
    dflag_entry[] entries
    int scope_depth
    string[] errors
}

struct dflag_result {
    bool ok
    string message
    string[] cleanup
}

func drop_flag_new() dflag_map {
    dflag_entry[] entries
    string[] errors
    dflag_map { entries: entries, scope_depth: 0, errors: errors }
}

func drop_flag_find(dflag_map flags, string name) int {
    i := len(flags.entries) - 1
    for i >= 0 {
        if flags.entries[i].name == name { return i }
        i = i - 1
    }
    -1
}

func drop_flag_error(dflag_map flags, string message) dflag_map {
    flags.errors = append(flags.errors, message)
    flags
}

func drop_flag_declare(dflag_map flags, string name, string type_name) dflag_map {
    if drop_flag_find(flags, name) >= 0 {
        return drop_flag_error(flags, "duplicate variable: " + name)
    }
    flags.entries = append(flags.entries, dflag_entry {
        name: name, type_name: type_name, state: drop_state_present(), scope_depth: flags.scope_depth,
    })
    flags
}

func drop_flag_mark_present(dflag_map flags, string name) dflag_map {
    index := drop_flag_find(flags, name)
    if index < 0 { return drop_flag_error(flags, "unknown variable: " + name) }
    flags.entries[index].state = drop_state_present()
    flags
}

func drop_flag_mark_absent(dflag_map flags, string name, string reason) dflag_map {
    index := drop_flag_find(flags, name)
    if index < 0 { return drop_flag_error(flags, "unknown variable: " + name) }
    if flags.entries[index].state != drop_state_present() {
        return drop_flag_error(flags, reason + " of absent value: " + name)
    }
    flags.entries[index].state = drop_state_absent()
    flags
}

func drop_flag_use(dflag_map flags, string name) dflag_map {
    index := drop_flag_find(flags, name)
    if index < 0 { return drop_flag_error(flags, "unknown variable: " + name) }
    if flags.entries[index].state != drop_state_present() {
        return drop_flag_error(flags, "use after move or drop: " + name)
    }
    flags
}

func drop_flag_move(dflag_map flags, string from_name, string to_name) dflag_map {
    index := drop_flag_find(flags, from_name)
    if index < 0 { return drop_flag_error(flags, "unknown variable: " + from_name) }
    type_name := flags.entries[index].type_name
    flags = drop_flag_mark_absent(flags, from_name, "move")
    if len(flags.errors) > 0 { return flags }
    drop_flag_declare(flags, to_name, type_name)
}

func drop_flag_drop(dflag_map flags, string name) dflag_map {
    drop_flag_mark_absent(flags, name, "drop")
}

func drop_flag_enter_scope(dflag_map flags) dflag_map {
    flags.scope_depth = flags.scope_depth + 1
    flags
}

func drop_flag_exit_scope(dflag_map flags, dtor_registry registry) dflag_result {
    string[] cleanup
    i := len(flags.entries) - 1
    for i >= 0 {
        entry := flags.entries[i]
        if entry.scope_depth == flags.scope_depth && entry.state == drop_state_present() {
            if dtor_registry_needs_drop(registry, entry.type_name) {
                cleanup = append(cleanup, emit_drop_call(registry, entry.name, entry.type_name))
            }
            flags.entries[i].state = drop_state_absent()
        }
        i = i - 1
    }
    message := ""
    j := 0
    for j < len(flags.errors) {
        message = message + flags.errors[j] + ";"
        j = j + 1
    }
    dflag_result { ok: len(flags.errors) == 0, message: message, cleanup: cleanup }
}

func drop_flag_cleanup_names(dflag_map flags, dtor_registry registry) string[] {
    string[] cleanup
    i := len(flags.entries) - 1
    for i >= 0 {
        entry := flags.entries[i]
        if entry.state == drop_state_present() && dtor_registry_needs_drop(registry, entry.type_name) {
            cleanup = append(cleanup, entry.name)
        }
        i = i - 1
    }
    cleanup
}
