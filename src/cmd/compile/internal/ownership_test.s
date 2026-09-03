package compile.internal.ownership_test
use compile.internal.ownership.ownership_check_events

func run_ownership_checker_test() int {
    valid := string[] { "declare:count:int", "move:count", "use:count", "scope_exit" }
    if ownership_check_events(valid).ok == false {
        return 1
    }
    moved := string[] { "declare:text:string", "move:text", "use:text" }
    if ownership_check_events(moved).ok {
        return 2
    }
    drops := string[] { "declare:left:string", "declare:right:Vec", "move:left", "scope_exit" }
    result := ownership_check_events(drops)
    if result.ok == false || len(result.drops) != 1 || result.drops[0] != "right" {
        return 3
    }
    0
}
