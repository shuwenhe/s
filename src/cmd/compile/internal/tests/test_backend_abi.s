package compile.internal.tests.test_backend_abi

use compile.internal.backend_elf64.build_abi_emit_plan
use compile.internal.backend_elf64.build_dwarf_like_artifact
use compile.internal.backend_elf64.build_gc_metadata_artifact
use compile.internal.backend_elf64.build_abi_machine_matrix_artifact
use compile.internal.backend_elf64.build_toolchain_compat_artifact
use compile.internal.backend_elf64.build_backend_perf_baseline_artifact
use compile.internal.backend_elf64.build_cfi_artifact
use compile.internal.backend_elf64.build_wasm_binary_probe_plan
use compile.internal.backend_elf64.validate_cfi_artifact
use compile.internal.backend_elf64.validate_ssa_abi_contracts
use compile.internal.backend_elf64.validate_wasi_contract_source
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
    if !contains(dwarf, "gate dwarf_consumable=") {
        return 1
    }
    if !contains(dwarf, "policy debug_budget_mode=") {
        return 1
    }
    if !contains(dwarf, "metric location_continuity=") {
        return 1
    }

    var gcmap = build_gc_metadata_artifact("amd64", parsed.unwrap(), "ssa pair blocks=2 values=4 loops=1 spills=2 rollback=0 proof_fail=0")
    if !contains(gcmap, "gcmap version=1") {
        return 1
    }
    if !contains(gcmap, "safepoints=") {
        return 1
    }
    if !contains(gcmap, "ptr_bitmap=") {
        return 1
    }
    if !contains(gcmap, "proof rollback=0 proof_fail=0") {
        return 1
    }
    if !contains(gcmap, "fault_inject ") {
        return 1
    }
    if !contains(gcmap, "stress baseline=enabled") {
        return 1
    }
    if !contains(gcmap, "contract e2e_safepoint=") {
        return 1
    }

    var matrix = build_abi_machine_matrix_artifact("amd64", parsed.unwrap(), "ssa pair blocks=2 values=4 spills=2")
    if !contains(matrix, "abi-matrix version=1") {
        return 1
    }
    if !contains(matrix, "matrix callseq=") {
        return 1
    }
    if !contains(matrix, "matrix ret=") {
        return 1
    }
    if !contains(matrix, "cross_arch_consistency=") {
        return 1
    }

    var toolchain = build_toolchain_compat_artifact(parsed.unwrap(), "amd64")
    if !contains(toolchain, "toolchain-compat version=1") {
        return 1
    }
    if !contains(toolchain, "module=") {
        return 1
    }
    if !contains(toolchain, "linker=") {
        return 1
    }
    if !contains(toolchain, "go_cmd_equiv=") {
        return 1
    }
    if !contains(toolchain, "matrix ") {
        return 1
    }
    if !contains(toolchain, "gate coverage=") {
        return 1
    }
    if !contains(toolchain, "interop cgo=") {
        return 1
    }
    if !contains(toolchain, "go_equiv ") {
        return 1
    }

    var perf = build_backend_perf_baseline_artifact("amd64", "ssa pair blocks=2 values=4 spills=2 splits=1 remat=1 sched_tp=8 sched_lat=5", "midend inline_sites=2")
    if !contains(perf, "perf-baseline version=1") {
        return 1
    }
    if !contains(perf, "regression_gate ") {
        return 1
    }
    if !contains(perf, "regression_gate_long ") {
        return 1
    }
    if !contains(perf, "regression_gate_arch ") {
        return 1
    }

    var cfi = build_cfi_artifact("amd64", "ssa pair blocks=2 spills=1 reloads=1", "ssa.debug pair")
    if !contains(cfi, ".cfi_startproc") {
        return 1
    }
    if !contains(cfi, ".cfi_endproc") {
        return 1
    }
    if validate_cfi_artifact(cfi).is_err() {
        return 1
    }

    if validate_ssa_abi_contracts("amd64", "spills=3 reloads=1 call_pressure=2").is_ok() {
        return 1
    }
    if validate_ssa_abi_contracts("amd64", "spills=1 reloads=2 call_pressure=2").is_err() {
        return 1
    }
    if validate_ssa_abi_contracts("amd64", "spills=1 reloads=2 call_pressure=2 callee_saved_clobber=1").is_ok() {
        return 1
    }
    if validate_ssa_abi_contracts("amd64", "spills=1 reloads=2 call_pressure=2 caller_restore_missing=1").is_ok() {
        return 1
    }

    var wasm_probe = build_wasm_binary_probe_plan("/tmp/out.wasm")
    if !contains(wasm_probe, "wasm-objdump -x /tmp/out.wasm") {
        return 1
    }
    if !contains(wasm_probe, "grep -q wasi_snapshot_preview1") {
        return 1
    }
    if !contains(wasm_probe, "grep -q _start") {
        return 1
    }

    var wasm_source = "__attribute__((__import_module__(\"wasi_snapshot_preview1\"), __import_name__(\"fd_write\")))\nextern int fd_write();\n__attribute__((__import_module__(\"wasi_snapshot_preview1\"), __import_name__(\"proc_exit\")))\nextern void proc_exit(int);\nint s_main(void){return 0;}\nvoid _start(void){proc_exit(s_main());}"
    if validate_wasi_contract_source(wasm_source).is_err() {
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
