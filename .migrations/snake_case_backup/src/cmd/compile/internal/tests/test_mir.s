package compile.internal.tests.testMir

use compile.internal.mir.TraceBranch
use compile.internal.mir.TraceLoop
use compile.internal.mir.TraceSwitch

func RunMirSuite() int32 {
    if TraceBranch("flag", "then", "else") != "branch flag |   then then |   else else" {
        return 1
    }
    if TraceLoop("while", "cond", "body") != "while cond |   body body" {
        return 1
    }
    if TraceSwitch("value", "arms") != "switch value | arms" {
        return 1
    }
    if TraceSwitch("value", "") != "switch value" {
        return 1
    }
    0
}
