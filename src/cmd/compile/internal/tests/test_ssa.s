package compile.internal.tests.test_ssa

use compile.internal.ssa_core.build_pipeline
use compile.internal.ssa_core.dump_pipeline
use std.prelude.slice

func run_ssa_suite() int32 {
    var mir_text = "mir main blocks=2 entry=0 exit=1 | bb0(entry) stmts=1 term=jump | bb1(exit) stmts=0 term=return"

    var arm64_dump = dump_pipeline(build_pipeline(mir_text, "arm64"))
    if !contains(arm64_dump, "blocks=2") {
        return 1
    }
    if !contains(arm64_dump, "v0->x9") {
        return 1
    }

    var amd64_dump = dump_pipeline(build_pipeline(mir_text, "amd64"))
    if !contains(amd64_dump, "v0->r10") {
        return 1
    }

    0
}

func contains(string text, string needle) bool {
    if needle == "" {
        return true
    }
    if text.len() < needle.len() {
        return false
    }

    var i = 0
    while i <= text.len() - needle.len() {
        if slice(text, i, i + needle.len()) == needle {
            return true
        }
        i = i + 1
    }
    false
}