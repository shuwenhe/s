package compile.internal.tests.test_mir

use compile.internal.mir.trace_branch
use compile.internal.mir.trace_loop
use compile.internal.mir.trace_switch

func run_mir_suite() int32 {
    if trace_branch("flag", "then", "else") != "branch flag |   then then |   else else" {
        return 1
    }
    if trace_loop("while", "cond", "body") != "while cond |   body body" {
        return 1
    }
    if trace_switch("value", "arms") != "switch value | arms" {
        return 1
    }
    if trace_switch("value", "") != "switch value" {
        return 1
    }
    0
}
