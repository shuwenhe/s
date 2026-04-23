package compile.internal.tests.test_backend_abi

use compile.internal.backend_elf64.build_abi_emit_plan
use compile.internal.backend_elf64.build_dwarf_like_artifact
use compile.internal.syntax.parse_source
use std.prelude.slice

func run_backend_abi_suite() int32 {
    var src = "package demo.abi\nfunc pair(int32 a, int32 b) (int32, int32) {\n  a\n}\nfunc big(result[int32, string] a, result[int32, string] b, result[int32, string] c) result[int32, string] {\n  a\n}\nfunc triple(int32 a, int32 b, int32 c) (int32, int32, int32) {\n  a\n}"
    var parsed = parse_source(src)
    if parsed.is_err() {
        return 1
    }

    var plan = build_abi_emit_plan("amd64", parsed.unwrap())
    if !contains(plan, "abi-emit version=1 arch=amd64") {
        return 1
    }
    if !contains(plan, "fn pair") {
        return 1
    }
    if !contains(plan, "ret_arity=2") {
        return 1
    }
    if !contains(plan, "agg_mode=tuple2") {
        return 1
    }
    if !contains(plan, "ret0->%rax") {
        return 1
    }
    if !contains(plan, "ret1->%rdx") {
        return 1
    }
    if !contains(plan, "stack_align=16") {
        return 1
    }
    if !contains(plan, "caller_saved=") {
        return 1
    }
    if !contains(plan, "callee_saved=") {
        return 1
    }
    if !contains(plan, "callseq=") {
        return 1
    }

    if !contains(plan, "fn big") {
        return 1
    }
    if !contains(plan, "agg_mode=complex") {
        return 1
    }
    if !contains(plan, "ret->sret:%rdi") {
        return 1
    }

    if !contains(plan, "fn triple") {
        return 1
    }
    if !contains(plan, "tuple_parts=3") {
        return 1
    }

    var dwarf = build_dwarf_like_artifact(parsed.unwrap(), "ssa pair blocks=2 values=4 loops=1 dbg_lines=3", "ssa.debug pair | value#0 reg=r10 | var v0 -> r10")
    if !contains(dwarf, "section .debug_loc") {
        return 1
    }
    if !contains(dwarf, "loc#0") {
        return 1
    }
    if !contains(dwarf, "section .debug_ranges") {
        return 1
    }
    if !contains(dwarf, "inline_range=") {
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
