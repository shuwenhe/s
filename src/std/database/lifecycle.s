package std.database

// Driver-owned bookkeeping only: this struct does not acquire an OS resource.
// Live owners must not be copied. Keep one mutable state with the native handle.
struct resource_state { bool open, bool busy, int children }
enum transaction_state { active, failed, committed, rolled_back }
func start_command(resource_state* state) error {
    if !state.open { return failure(error_closed,"resource is closed") }
    if state.busy { return failure(error_busy,"previous command is active") }
    state.busy = true
    return error { code: 0 }
}
func finish_command(resource_state* state) error {
    if !state.open { return failure(error_closed,"resource is closed") }
    if !state.busy { return failure(error_invalid,"no command is active") }
    state.busy = false
    return error { code: 0 }
}
func retain_child(resource_state* state) error {
    if !state.open { return failure(error_closed,"parent is closed") }
    if state.children < 0 || state.children == 9223372036854775807 { return failure(error_overflow,"resource child count overflow") }
    state.children = state.children + 1
    return error { code: 0 }
}
func release_child(resource_state* state) error {
    if !state.open { return failure(error_closed,"parent is closed") }
    if state.children <= 0 { return failure(error_invalid,"no retained child") }
    state.children = state.children - 1
    return error { code: 0 }
}
// Invoke after native cleanup succeeds, never in place of native cleanup.
func close_resource(resource_state* state) error {
    if !state.open { return error { code: 0 } }
    if state.busy || state.children != 0 { return failure(error_busy,"resource has active work or children") }
    state.open = false
    return error { code: 0 }
}
func transaction_can_execute(transaction_state state) error {
    switch state {
        transaction_state::active : { return error { code: 0 } },
        transaction_state::failed : return failure(error_invalid,"transaction failed; rollback required"),
        _ : return failure(error_closed,"transaction has finished"),
    }
}
func transaction_can_finish(transaction_state state, bool commit) error {
    switch state {
        transaction_state::active : { return error { code: 0 } },
        transaction_state::failed : {
            if commit { return failure(error_invalid,"failed transaction cannot commit") }
            return error { code: 0 }
        },
        _ : return failure(error_closed,"transaction has finished"),
    }
}
