package compile.internal.tests.test_backend_abi

use compile.internal.backend_elf64.build_abi_emit_plan
use compile.internal.backend_elf64.build_dwarf_like_artifact
use compile.internal.backend_elf64.build_gc_metadata_artifact
use compile.internal.backend_elf64.build_abi_machine_matrix_artifact
use compile.internal.backend_elf64.build_toolchain_compat_artifact
use compile.internal.backend_elf64.build_go_asm_bridge_artifact
use compile.internal.backend_elf64.build_backend_perf_baseline_artifact
use compile.internal.backend_elf64.build_cfi_artifact
use compile.internal.backend_elf64.build_wasm_binary_probe_plan
use compile.internal.backend_elf64.compile_writes
use compile.internal.backend_elf64.compile_exit_code
use compile.internal.backend_elf64.translate_go_plan9_to_gas
use compile.internal.backend_elf64.validate_cfi_artifact
use compile.internal.backend_elf64.validate_go_asm_bridge_artifact
use compile.internal.backend_elf64.validate_ssa_abi_contracts
use compile.internal.backend_elf64.validate_wasi_contract_source
use compile.internal.ir.lower.lower_main_to_mir
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
    if !contains(toolchain, "asm=go-plan9-min") {
        return 1
    }
    if !contains(toolchain, "go_asm syntax=plan9 translator=enabled status=ok") {
        return 1
    }
    if !contains(toolchain, "go_equiv ") {
        return 1
    }

    var go_asm_src = "TEXT main(SB),$0-0\nMOVQ $7, AX\nADDQ $3, AX\nRET\n"
    var gas = translate_go_plan9_to_gas("amd64", go_asm_src)
    if gas.is_err() {
        return 1
    }
    if !contains(gas.unwrap(), ".globl main") {
        return 1
    }
    if !contains(gas.unwrap(), "movq $7, %rax") {
        return 1
    }
    if !contains(gas.unwrap(), "addq $3, %rax") {
        return 1
    }
    if !contains(gas.unwrap(), "ret") {
        return 1
    }

    var asm_artifact = build_go_asm_bridge_artifact("amd64", go_asm_src)
    if validate_go_asm_bridge_artifact(asm_artifact).is_err() {
        return 1
    }

    var bad_go_asm = "MOVQ $1, AX\nRET\n"
    if translate_go_plan9_to_gas("amd64", bad_go_asm).is_ok() {
        return 1
    }

    var go_asm_ctrl = "TEXT helper(SB),$0-0\nMOVQ ret+8(FP), AX\nRET\nTEXT main(SB),$0-0\nCALL helper(SB)\nCMPQ AX, AX\nJE done\nJMP done\ndone:\nRET\n"
    var gas_ctrl = translate_go_plan9_to_gas("amd64", go_asm_ctrl)
    if gas_ctrl.is_err() {
        return 1
    }
    if !contains(gas_ctrl.unwrap(), "helper:") {
        return 1
    }
    if !contains(gas_ctrl.unwrap(), "movq 8(%rbp), %rax") {
        return 1
    }
    if !contains(gas_ctrl.unwrap(), "call helper") {
        return 1
    }
    if !contains(gas_ctrl.unwrap(), "je done") {
        return 1
    }
    if !contains(gas_ctrl.unwrap(), "done:") {
        return 1
    }

    var bad_go_asm_base = "TEXT main(SB),$0-0\nMOVQ 0(X0), AX\nRET\n"
    if translate_go_plan9_to_gas("amd64", bad_go_asm_base).is_ok() {
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

    var fn_map_src = "package demo.fnmap\nfunc arm64_init() int32 {\n  println(\"arm64\")\n  0\n}\nfunc amd64_init() int32 {\n  println(\"amd64\")\n  0\n}\nfunc main() int32 {\n  var archInits = map[string]func() int32{\"amd64\": amd64_init, \"arm64\": arm64_init}\n  var goarch = \"arm64\"\n  var init = archInits[goarch]\n  init()\n  0\n}"
    var fn_map_parsed = parse_source(fn_map_src)
    if fn_map_parsed.is_err() {
        return 1
    }
    var fn_map_graph = lower_main_to_mir(fn_map_parsed.unwrap())
    if fn_map_graph.is_err() {
        return 1
    }
    var fn_map_writes = compile_writes(fn_map_parsed.unwrap(), fn_map_graph.unwrap())
    if fn_map_writes.is_err() {
        return 1
    }
    if fn_map_writes.unwrap().len() == 0 {
        return 1
    }
    if fn_map_writes.unwrap()[0].text != "arm64\n" {
        return 1
    }
    var fn_map_exit = compile_exit_code(fn_map_parsed.unwrap(), fn_map_graph.unwrap())
    if fn_map_exit.is_err() {
        return 1
    }
    if fn_map_exit.unwrap() != 0 {
        return 1
    }

    var defer_src = "package demo.defer\nfunc main() int32 {\n  defer println(\"cleanup\")\n  println(\"work\")\n  0\n}"
    var defer_parsed = parse_source(defer_src)
    if defer_parsed.is_err() {
        return 1
    }
    var defer_graph = lower_main_to_mir(defer_parsed.unwrap())
    if defer_graph.is_err() {
        return 1
    }
    var defer_writes = compile_writes(defer_parsed.unwrap(), defer_graph.unwrap())
    if defer_writes.is_err() {
        return 1
    }
    if defer_writes.unwrap().len() != 2 {
        return 1
    }
    if defer_writes.unwrap()[0].text != "work\n" {
        return 1
    }
    if defer_writes.unwrap()[1].text != "cleanup\n" {
        return 1
    }
    var defer_exit = compile_exit_code(defer_parsed.unwrap(), defer_graph.unwrap())
    if defer_exit.is_err() {
        return 1
    }
    if defer_exit.unwrap() != 0 {
        return 1
    }

    var recover_src = "package demo.recover\nfunc handle() int32 {\n  recover()\n  println(\"recovered\")\n  0\n}\nfunc main() int32 {\n  defer handle()\n  panic(\"boom\")\n  0\n}"
    var recover_parsed = parse_source(recover_src)
    if recover_parsed.is_err() {
        return 1
    }
    var recover_graph = lower_main_to_mir(recover_parsed.unwrap())
    if recover_graph.is_err() {
        return 1
    }
    var recover_writes = compile_writes(recover_parsed.unwrap(), recover_graph.unwrap())
    if recover_writes.is_err() {
        return 1
    }
    if recover_writes.unwrap().len() != 1 {
        return 1
    }
    if recover_writes.unwrap()[0].text != "recovered\n" {
        return 1
    }
    var recover_exit = compile_exit_code(recover_parsed.unwrap(), recover_graph.unwrap())
    if recover_exit.is_err() {
        return 1
    }
    if recover_exit.unwrap() != 0 {
        return 1
    }

    var const_iota_src = "package demo.consts\nconst (\n  A = iota\n  B\n)\nconst C = 10 / B\nfunc main() int32 {\n  println(C)\n  0\n}"
    var const_iota_parsed = parse_source(const_iota_src)
    if const_iota_parsed.is_err() {
        return 1
    }
    var const_iota_graph = lower_main_to_mir(const_iota_parsed.unwrap())
    if const_iota_graph.is_err() {
        return 1
    }
    var const_iota_writes = compile_writes(const_iota_parsed.unwrap(), const_iota_graph.unwrap())
    if const_iota_writes.is_err() {
        return 1
    }
    if const_iota_writes.unwrap().len() == 0 {
        return 1
    }
    if const_iota_writes.unwrap()[0].text != "10\n" {
        return 1
    }

    var const_iota_fail_src = "package demo.consts\nconst (\n  A = iota\n  B = 10 / A\n)\nfunc main() int32 {\n  0\n}"
    var const_iota_fail_parsed = parse_source(const_iota_fail_src)
    if const_iota_fail_parsed.is_err() {
        return 1
    }
    var const_iota_fail_graph = lower_main_to_mir(const_iota_fail_parsed.unwrap())
    if const_iota_fail_graph.is_err() {
        return 1
    }
    var const_iota_fail_writes = compile_writes(const_iota_fail_parsed.unwrap(), const_iota_fail_graph.unwrap())
    if const_iota_fail_writes.is_ok() {
        return 1
    }
    if !contains(const_iota_fail_writes.unwrap_err().message, "const evaluation failed") {
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
