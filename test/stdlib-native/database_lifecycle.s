package main
import "std.database"
func main() int {
    state := std.database.resource_state { open: true, busy: false, children: 0 }
    if std.database.start_command(state*).code != 0 { return 1 }
    if std.database.start_command(state*).code != std.database.error_busy { return 2 }
    if std.database.close_resource(state*).code != std.database.error_busy { return 3 }
    if std.database.finish_command(state*).code != 0 { return 4 }
    if std.database.retain_child(state*).code != 0 { return 5 }
    if std.database.close_resource(state*).code != std.database.error_busy { return 6 }
    if std.database.release_child(state*).code != 0 { return 7 }
    if std.database.release_child(state*).code != std.database.error_invalid { return 8 }
    if std.database.close_resource(state*).code != 0 { return 9 }
    if std.database.close_resource(state*).code != 0 { return 10 }
    if std.database.start_command(state*).code != std.database.error_closed { return 11 }
    if std.database.retain_child(state*).code != std.database.error_closed { return 12 }
    active := std.database.transaction_state.active
    if std.database.transaction_can_execute(active).code != 0 { return 13 }
    if std.database.transaction_can_execute(std.database.transaction_state.failed).code == 0 { return 14 }
    if std.database.transaction_can_finish(std.database.transaction_state.failed,false).code != 0 { return 15 }
    if std.database.transaction_can_finish(std.database.transaction_state.failed,true).code == 0 { return 16 }
    if std.database.transaction_can_finish(std.database.transaction_state.committed,false).code != std.database.error_closed { return 17 }
    if std.database.transaction_can_finish(std.database.transaction_state.rolled_back,true).code != std.database.error_closed { return 18 }
    println("database lifecycle: PASS")
    return 0
}
