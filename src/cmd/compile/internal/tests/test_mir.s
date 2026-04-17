package compile.internal.tests.test_mir

use compile.internal.mir.TraceBranch
use compile.internal.mir.TraceLoop
use compile.internal.mir.TraceMatch

func RunMirSuite() int32 {
    if TraceBranch("flag", "then", "else") != "branch flag |   then then |   else else" {
        return 1
    }
    if TraceLoop("while", "cond", "body") != "while cond |   body body" {
        return 1
    }
    if TraceMatch("value", "arms") != "match value | arms" {
        return 1
    }
    if TraceMatch("value", "") != "match value" {
        return 1
    }
    0
}
