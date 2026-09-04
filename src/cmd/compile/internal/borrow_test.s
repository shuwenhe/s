package compile.internal.borrow_test
use compile.internal.borrow.borrow_check_events
use compile.internal.borrow.lifetime_check_events
use compile.internal.borrow.ownership_check_events

func run_borrow_checker_test() int {
    shared_ok := string[] { "declare:x", "shared:x", "shared:x", "read:x", "end_shared:x", "end_shared:x", "write:x" }
    if borrow_check_events(shared_ok).ok == false {
        return 1
    }
    shared_mut_conflict := string[] { "declare:x", "shared:x", "mutable:x" }
    if borrow_check_events(shared_mut_conflict).ok {
        return 2
    }
    mutable_shared_conflict := string[] { "declare:x", "mutable:x", "shared:x" }
    if borrow_check_events(mutable_shared_conflict).ok {
        return 3
    }
    mutable_mut_conflict := string[] { "declare:x", "mutable:x", "mutable:x" }
    if borrow_check_events(mutable_mut_conflict).ok {
        return 4
    }
    move_conflict := string[] { "declare:text", "move:text", "read:text" }
    if borrow_check_events(move_conflict).ok {
        return 5
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
    shorter_owner := string[] { "scope:outer", "scope:inner", "borrow:r:inner:outer" }
    if lifetime_check_events(shorter_owner).ok {
        return 3
    }
    ended_owner := string[] { "scope:outer", "end_scope:outer", "scope:inner", "borrow:r:outer:inner" }
    if lifetime_check_events(ended_owner).ok {
        return 4
    }
    ended := string[] { "scope:outer", "scope:inner", "borrow:r:outer:inner", "end_borrow:r", "use_ref:r" }
    if lifetime_check_events(ended).ok {
        return 5
    }
    0
}

func run_ownership_checker_test() int {
    copy_ok := string[] { "declare:n:copy", "copy:n", "use:n", "drop:n" }
    if ownership_check_events(copy_ok).ok == false {
        return 1
    }
    move_use_fail := string[] { "declare:text:move", "move:text", "use:text" }
    if ownership_check_events(move_use_fail).ok {
        return 2
    }
    noncopy_fail := string[] { "declare:text:move", "copy:text" }
    if ownership_check_events(noncopy_fail).ok {
        return 3
    }
    double_drop_fail := string[] { "declare:file:move", "drop:file", "drop:file" }
    if ownership_check_events(double_drop_fail).ok {
        return 4
    }
    unknown_place_fail := string[] { "use:missing" }
    if ownership_check_events(unknown_place_fail).ok {
        return 5
    }
    0
}
