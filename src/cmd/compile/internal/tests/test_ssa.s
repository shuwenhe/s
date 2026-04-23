package compile.internal.tests.test_ssa

use compile.internal.ssa_core.build_pipeline
use compile.internal.ssa_core.dump_pipeline
use compile.internal.ssa_core.dump_debug_map
use std.prelude.slice

func run_ssa_suite() int32 {
    var mir_text = "mir main blocks=2 entry=0 exit=1 | bb0(entry) stmts=1 term=jump | bb1(exit) stmts=0 term=return"

    var arm64_dump = dump_pipeline(build_pipeline(mir_text, "arm64"))
    if !contains(arm64_dump, "blocks=2") {
        return 1
    }
    if !contains(arm64_dump, "opt_values=") {
        return 1
    }
    if !contains(arm64_dump, "folded=") {
        return 1
    }
    if !contains(arm64_dump, "dce=") {
        return 1
    }
    if !contains(arm64_dump, "v0->x9") {
        return 1
    }
    if !contains(arm64_dump, "cfg_edges=") {
        return 1
    }

    var amd64_program = build_pipeline(mir_text, "amd64")
    var amd64_dump = dump_pipeline(amd64_program)
    if !contains(amd64_dump, "v0->r10") {
        return 1
    }
    var debug_map = dump_debug_map(amd64_program)
    if !contains(debug_map, "ssa.debug") {
        return 1
    }
    if !contains(debug_map, "value#0") {
        return 1
    }
    if !contains(debug_map, "line 100") {
        return 1
    }

    var heavy_mir = "mir heavy blocks=3 entry=0 exit=2 | bb0(entry) stmts=12 term=branch | bb1(mid) stmts=8 term=jump | bb2(exit) stmts=0 term=return"
    var heavy_dump = dump_pipeline(build_pipeline(heavy_mir, "amd64"))
    if !contains(heavy_dump, "spills=") {
        return 1
    }
    if !contains(heavy_dump, "spill(") {
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