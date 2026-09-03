package compile.internal.borrow_test
use compile.internal.borrow.borrow_check_events
use compile.internal.borrow.lifetime_check_events

func run_borrow_checker_test() int {
    shared_ok := string[] { "shared:x", "shared:x", "read:x", "end_shared:x", "end_shared:x", "write:x" }
    if borrow_check_events(shared_ok).ok == false {
        return 1
    }
    shared_mut_conflict := string[] { "shared:x", "mutable:x" }
    if borrow_check_events(shared_mut_conflict).ok {
        return 2
    }
    move_conflict := string[] { "move:text", "read:text" }
    if borrow_check_events(move_conflict).ok {
        return 3
    }
    0
}

func run_lifetime_checker_test() int {
    valid := string[] { "scope:outer", "scope:inner", "borrow:r:outer:inner", "use_ref:r", "end_borrow:r", "end_scope:inner", "end_scope:outer" }
    if lifetime_check_events(valid).ok == false {
        return 1
    }
    dangling := string[] { "scope:outer", "scope:inner", "borrow:r:outer:inner", "end_scope:outer", "use_ref:r" }
    if lifetime_check_events(dangling).ok {
        return 2
    }
    ended := string[] { "scope:outer", "scope:inner", "borrow:r:outer:inner", "end_borrow:r", "use_ref:r" }
    if lifetime_check_events(ended).ok {
        return 3
    }
    0
}
