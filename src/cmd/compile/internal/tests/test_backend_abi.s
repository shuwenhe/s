package compile.internal.tests.test_backend_abi

use compile.internal.backend_elf64.build_abi_emit_plan
use compile.internal.backend_elf64.build_dwarf_like_artifact
use compile.internal.backend_elf64.build_gc_metadata_artifact
use compile.internal.backend_elf64.build_abi_machine_matrix_artifact
use compile.internal.backend_elf64.build_toolchain_compat_artifact
use compile.internal.backend_elf64.build_go_asm_bridge_artifact
use compile.internal.backend_elf64.build_backend_perf_baseline_artifact
use compile.internal.backend_elf64.build_midend_opt_artifact
use compile.internal.backend_elf64.build
use compile.internal.backend_elf64.build_cfi_artifact
use compile.internal.backend_elf64.build_wasm_binary_probe_plan
use compile.internal.backend_elf64.compile_writes
use compile.internal.backend_elf64.compile_exit_code
use compile.internal.backend_elf64.compile_runtime_metrics
use compile.internal.backend_elf64.translate_go_plan9_to_gas
use compile.internal.backend_elf64.validate_backend_perf_baseline
use compile.internal.backend_elf64.validate_cfi_artifact
use compile.internal.backend_elf64.validate_dwarf_consumability
use compile.internal.backend_elf64.validate_go_asm_bridge_artifact
use compile.internal.backend_elf64.validate_midend_opt_artifact
use compile.internal.backend_elf64.validate_ssa_abi_contracts
use compile.internal.backend_elf64.validate_toolchain_compat_artifact
use compile.internal.backend_elf64.validate_wasi_contract_source
use compile.internal.ir.lower.lower_main_to_mir
use compile.internal.syntax.parse_source
use std.fs.make_temp_dir
use std.fs.read_to_string
use std.fs.write_text_file
use std.prelude.slice

func run_backend_abi_suite() int {
    var src = "package demo.abi\nfunc pair(int a, int b) (int, int) {\n  a\n}\nfunc big(result[int, string] a, result[int, string] b, result[int, string] c) result[int, string] {\n  a\n}\nfunc triple(int a, int b, int c) (int, int, int) {\n  a\n}"
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
    if !contains(plan, "abi_in_regs=") {
        return 1
    }
    if !contains(plan, "abi_spill=") {
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
    if !contains(gcmap, "collector plan=go-like-mark-sweep") {
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

    var perf = build_backend_perf_baseline_artifact(
        "amd64",
        "ssa pair blocks=2 values=4 spills=2 splits=1 remat=1 sched_tp=8 sched_lat=5",
        "midend inline_sites=2 sroutine_sites=1 select_weighted_sites=1 select_timeout_sites=1 select_send_sites=1",
        "runtime_sched sroutine_scheduled=1 sroutine_completed=1 sroutine_panics=0 sroutine_recovered=0 sroutine_yields=1 select_attempts=2 select_default_fallbacks=1 select_timeouts=1 channels=1 channel_sends=1 channel_recvs=1 channel_closed=1"
    )
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
    if !contains(perf, "scheduler queue_policy=priority-rr select_policy=multi-chan-priority-rr") {
        return 1
    }
    if !contains(perf, "select_weighted_sites=1 select_timeout_sites=1 select_send_sites=1") {
        return 1
    }
    if !contains(perf, "runtime_sched sroutine_scheduled=") {
        return 1
    }
    if !contains(perf, "scheduler_counters select_default_fallbacks=1 select_timeouts=1") {
        return 1
    }
    if !contains(perf, "runtime_gc cycles=") {
        return 1
    }

    var opt = build_midend_opt_artifact(
        "midend inline_sites=2 escape_sites=1 devirtualized=1 cross_pkg_inline=0 const_prop=1 sroutine_sites=1 select_weighted_sites=1 select_timeout_sites=1 select_send_sites=1 const_fold_hits=2 ipo_synergy=3 pass_rm_unreachable=1 pass_fold_branch=1 pass_simplify_j2r=0 pass_trim_unit=0 pass_dedup=1"
    )
    if !contains(opt, "midend-opt version=1") {
        return 1
    }
    if !contains(opt, "report midend inline_sites=2") {
        return 1
    }
    if !contains(opt, "scheduler_opt sroutine_sites=1 select_weighted_sites=1 select_timeout_sites=1 select_send_sites=1") {
        return 1
    }
    if !contains(opt, "passes rm_unreachable=1 fold_branch=1 simplify_j2r=0 trim_unit=0 dedup=1 ipo_synergy=3") {
        return 1
    }
    if validate_midend_opt_artifact(opt).is_err() {
        return 1
    }

    var e2e_temp = make_temp_dir("s-opt-e2e-")
    if e2e_temp.is_err() {
        return 1
    }
    var e2e_dir = e2e_temp.unwrap()
    var e2e_src_path = e2e_dir + "/select_opt_demo.s"
    var e2e_out_path = e2e_dir + "/select_opt_demo"
    var e2e_src = "package demo.opte2e\nfunc worker() int {\n  chan_send(ch1, 7)\n  0\n}\nfunc main() int {\n  var ch1 = chan_make(1)\n  sroutine worker()\n  println(select_recv_timeout(ch1, 2))\n  select_send(ch1, 9)\n  println(chan_recv(ch1))\n  chan_close(ch1)\n  0\n}"
    if write_text_file(e2e_src_path, e2e_src).is_err() {
        return 1
    }
    if build(e2e_src_path, e2e_out_path, "") != 0 {
        return 1
    }
    if !validate_emitted_artifacts(e2e_out_path) {
        return 1
    }
    if build(e2e_src_path, e2e_out_path + ".badmargin", "oops") == 0 {
        return 1
    }

    var e2e_nomaint_src_path = e2e_dir + "/missing_main_demo.s"
    var e2e_nomaint_out_path = e2e_dir + "/missing_main_demo"
    var e2e_missing_main_src = "package demo.nomian\nfunc helper() int {\n  0\n}"
    if write_text_file(e2e_nomaint_src_path, e2e_missing_main_src).is_err() {
        return 1
    }
    if build(e2e_nomaint_src_path, e2e_nomaint_out_path, "") == 0 {
        return 1
    }

    var e2e_semantic_src_path = e2e_dir + "/semantic_fail_demo.s"
    var e2e_semantic_out_path = e2e_dir + "/semantic_fail_demo"
    var e2e_semantic_fail_src = "package demo.semanticfail\nfunc main() int {\n  missing()\n  0\n}"
    if write_text_file(e2e_semantic_src_path, e2e_semantic_fail_src).is_err() {
        return 1
    }
    if build(e2e_semantic_src_path, e2e_semantic_out_path, "") == 0 {
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

    var fn_map_src = "package demo.fnmap\nfunc arm64_init() int {\n  println(\"arm64\")\n  0\n}\nfunc amd64_init() int {\n  println(\"amd64\")\n  0\n}\nfunc main() int {\n  var archInits = map[string]func() int{\"amd64\": amd64_init, \"arm64\": arm64_init}\n  var goarch = \"arm64\"\n  var init = archInits[goarch]\n  init()\n  0\n}"
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

    var defer_src = "package demo.defer\nfunc main() int {\n  defer println(\"cleanup\")\n  println(\"work\")\n  0\n}"
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

    var recover_src = "package demo.recover\nfunc handle() int {\n  recover()\n  println(\"recovered\")\n  0\n}\nfunc main() int {\n  defer handle()\n  panic(\"boom\")\n  0\n}"
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

    var sroutine_src = "package demo.sroutine\nfunc worker() int {\n  println(\"worker\")\n  0\n}\nfunc main() int {\n  sroutine worker()\n  println(\"main\")\n  0\n}"
    var sroutine_parsed = parse_source(sroutine_src)
    if sroutine_parsed.is_err() {
        return 1
    }
    var sroutine_graph = lower_main_to_mir(sroutine_parsed.unwrap())
    if sroutine_graph.is_err() {
        return 1
    }
    var sroutine_writes = compile_writes(sroutine_parsed.unwrap(), sroutine_graph.unwrap())
    if sroutine_writes.is_err() {
        return 1
    }
    if sroutine_writes.unwrap().len() != 2 {
        return 1
    }
    if sroutine_writes.unwrap()[0].text != "worker\n" {
        return 1
    }
    if sroutine_writes.unwrap()[1].text != "main\n" {
        return 1
    }
    var sroutine_exit = compile_exit_code(sroutine_parsed.unwrap(), sroutine_graph.unwrap())
    if sroutine_exit.is_err() {
        return 1
    }
    if sroutine_exit.unwrap() != 0 {
        return 1
    }

    var sroutine_chan_src = "package demo.sroutinechan\nfunc producer1() int {\n  chan_send(ch1, 1)\n  chan_send(ch1, 4)\n  0\n}\nfunc producer2() int {\n  chan_send(ch2, 2)\n  0\n}\nfunc main() int {\n  var ch1 = chan_make(3)\n  var ch2 = chan_make(3)\n  sroutine producer1()\n  sroutine producer2()\n  println(select_recv(ch1, ch2))\n  println(select_recv(ch1, ch2))\n  println(select_recv(ch1, ch2))\n  println(select_recv_default(ch1, ch2))\n  chan_close(ch1)\n  chan_close(ch2)\n  0\n}"
    var sroutine_chan_parsed = parse_source(sroutine_chan_src)
    if sroutine_chan_parsed.is_err() {
        return 1
    }
    var sroutine_chan_graph = lower_main_to_mir(sroutine_chan_parsed.unwrap())
    if sroutine_chan_graph.is_err() {
        return 1
    }
    var sroutine_chan_writes = compile_writes(sroutine_chan_parsed.unwrap(), sroutine_chan_graph.unwrap())
    if sroutine_chan_writes.is_err() {
        return 1
    }
    if sroutine_chan_writes.unwrap().len() != 4 {
        return 1
    }
    if sroutine_chan_writes.unwrap()[0].text != "1\n" {
        return 1
    }
    if sroutine_chan_writes.unwrap()[1].text != "2\n" {
        return 1
    }
    if sroutine_chan_writes.unwrap()[2].text != "4\n" {
        return 1
    }
    if sroutine_chan_writes.unwrap()[3].text != "()\n" {
        return 1
    }
    var sroutine_chan_metrics = compile_runtime_metrics(sroutine_chan_parsed.unwrap(), sroutine_chan_graph.unwrap())
    if sroutine_chan_metrics.is_err() {
        return 1
    }
    if sroutine_chan_metrics.unwrap().select_attempts != 4 {
        return 1
    }
    if sroutine_chan_metrics.unwrap().select_default_fallbacks != 1 {
        return 1
    }
    if sroutine_chan_metrics.unwrap().channel_sends != 3 {
        return 1
    }
    if sroutine_chan_metrics.unwrap().channel_recvs != 3 {
        return 1
    }

    var gc_collect_src = "package demo.gc\nfunc allocate_temp() int {\n  var temp = chan_make(1)\n  0\n}\nfunc main() int {\n  var survivor = chan_make(1)\n  allocate_temp()\n  gc_collect()\n  println(survivor)\n  0\n}"
    var gc_collect_parsed = parse_source(gc_collect_src)
    if gc_collect_parsed.is_err() {
        return 1
    }
    var gc_collect_graph = lower_main_to_mir(gc_collect_parsed.unwrap())
    if gc_collect_graph.is_err() {
        return 1
    }
    var gc_collect_writes = compile_writes(gc_collect_parsed.unwrap(), gc_collect_graph.unwrap())
    if gc_collect_writes.is_err() {
        return 1
    }
    if gc_collect_writes.unwrap().len() != 1 {
        return 1
    }
    if gc_collect_writes.unwrap()[0].text != "<chan:1>\n" {
        return 1
    }
    var gc_collect_metrics = compile_runtime_metrics(gc_collect_parsed.unwrap(), gc_collect_graph.unwrap())
    if gc_collect_metrics.is_err() {
        return 1
    }
    if gc_collect_metrics.unwrap().gc_cycles < 1 {
        return 1
    }
    if gc_collect_metrics.unwrap().gc_freed_channels < 1 {
        return 1
    }
    if gc_collect_metrics.unwrap().gc_live_channels != 1 {
        return 1
    }

    var gc_barrier_src = "package demo.gcbarrier\nfunc main() int {\n  var outer = chan_make(1)\n  var inner = chan_make(1)\n  select_send(outer, inner)\n  gc_collect()\n  println(chan_recv(outer))\n  0\n}"
    var gc_barrier_parsed = parse_source(gc_barrier_src)
    if gc_barrier_parsed.is_err() {
        return 1
    }
    var gc_barrier_graph = lower_main_to_mir(gc_barrier_parsed.unwrap())
    if gc_barrier_graph.is_err() {
        return 1
    }
    var gc_barrier_writes = compile_writes(gc_barrier_parsed.unwrap(), gc_barrier_graph.unwrap())
    if gc_barrier_writes.is_err() {
        return 1
    }
    if gc_barrier_writes.unwrap().len() != 1 {
        return 1
    }
    if gc_barrier_writes.unwrap()[0].text != "<chan:2>\n" {
        return 1
    }
    var gc_barrier_metrics = compile_runtime_metrics(gc_barrier_parsed.unwrap(), gc_barrier_graph.unwrap())
    if gc_barrier_metrics.is_err() {
        return 1
    }
    if gc_barrier_metrics.unwrap().gc_write_barriers != 1 {
        return 1
    }
    if gc_barrier_metrics.unwrap().gc_live_channels != 2 {
        return 1
    }

    var gc_auto_src = "package demo.gcauto\nfunc alloc_many() int {\n  var a = chan_make(1)\n  var b = chan_make(1)\n  var c = chan_make(1)\n  0\n}\nfunc main() int {\n  var survivor = chan_make(1)\n  alloc_many()\n  println(survivor)\n  0\n}"
    var gc_auto_parsed = parse_source(gc_auto_src)
    if gc_auto_parsed.is_err() {
        return 1
    }
    var gc_auto_graph = lower_main_to_mir(gc_auto_parsed.unwrap())
    if gc_auto_graph.is_err() {
        return 1
    }
    var gc_auto_writes = compile_writes(gc_auto_parsed.unwrap(), gc_auto_graph.unwrap())
    if gc_auto_writes.is_err() {
        return 1
    }
    if gc_auto_writes.unwrap().len() != 1 {
        return 1
    }
    if gc_auto_writes.unwrap()[0].text != "<chan:1>\n" {
        return 1
    }
    var gc_auto_metrics = compile_runtime_metrics(gc_auto_parsed.unwrap(), gc_auto_graph.unwrap())
    if gc_auto_metrics.is_err() {
        return 1
    }
    if gc_auto_metrics.unwrap().gc_triggered_cycles < 1 {
        return 1
    }
    if gc_auto_metrics.unwrap().gc_live_channels != 1 {
        return 1
    }

    var weighted_timeout_src = "package demo.weighted\nfunc producer1() int {\n  chan_send(ch1, 7)\n  0\n}\nfunc producer2() int {\n  chan_send(ch2, 9)\n  0\n}\nfunc main() int {\n  var ch1 = chan_make(2)\n  var ch2 = chan_make(2)\n  sroutine producer1()\n  sroutine producer2()\n  println(select_recv_weighted(ch1, 2, ch2, 1))\n  println(select_recv_timeout(ch1, ch2, 3))\n  println(select_recv_timeout(ch1, ch2, 3))\n  chan_close(ch1)\n  chan_close(ch2)\n  0\n}"
    var weighted_timeout_parsed = parse_source(weighted_timeout_src)
    if weighted_timeout_parsed.is_err() {
        return 1
    }
    var weighted_timeout_graph = lower_main_to_mir(weighted_timeout_parsed.unwrap())
    if weighted_timeout_graph.is_err() {
        return 1
    }
    var weighted_timeout_writes = compile_writes(weighted_timeout_parsed.unwrap(), weighted_timeout_graph.unwrap())
    if weighted_timeout_writes.is_err() {
        return 1
    }
    if weighted_timeout_writes.unwrap().len() != 3 {
        return 1
    }
    if weighted_timeout_writes.unwrap()[0].text != "7\n" {
        return 1
    }
    if weighted_timeout_writes.unwrap()[1].text != "9\n" {
        return 1
    }
    if weighted_timeout_writes.unwrap()[2].text != "()\n" {
        return 1
    }
    var weighted_timeout_metrics = compile_runtime_metrics(weighted_timeout_parsed.unwrap(), weighted_timeout_graph.unwrap())
    if weighted_timeout_metrics.is_err() {
        return 1
    }
    if weighted_timeout_metrics.unwrap().select_attempts != 3 {
        return 1
    }
    if weighted_timeout_metrics.unwrap().select_timeouts != 1 {
        return 1
    }
    if weighted_timeout_metrics.unwrap().select_default_fallbacks != 0 {
        return 1
    }

    var select_send_src = "package demo.selectsend\nfunc main() int {\n  var ch1 = chan_make(1)\n  var ch2 = chan_make(1)\n  select_send(ch1, 5, ch2, 6)\n  println(chan_recv(ch1))\n  select_send_default(ch1, 7, ch2, 8)\n  println(chan_recv(ch2))\n  select_send_timeout(ch1, 9, ch2, 10, 2)\n  println(chan_recv(ch1))\n  chan_close(ch1)\n  chan_close(ch2)\n  0\n}"
    var select_send_parsed = parse_source(select_send_src)
    if select_send_parsed.is_err() {
        return 1
    }
    var select_send_graph = lower_main_to_mir(select_send_parsed.unwrap())
    if select_send_graph.is_err() {
        return 1
    }
    var select_send_writes = compile_writes(select_send_parsed.unwrap(), select_send_graph.unwrap())
    if select_send_writes.is_err() {
        return 1
    }
    if select_send_writes.unwrap().len() != 3 {
        return 1
    }
    if select_send_writes.unwrap()[0].text != "5\n" {
        return 1
    }
    if select_send_writes.unwrap()[1].text != "8\n" {
        return 1
    }
    if select_send_writes.unwrap()[2].text != "7\n" {
        return 1
    }
    var select_send_metrics = compile_runtime_metrics(select_send_parsed.unwrap(), select_send_graph.unwrap())
    if select_send_metrics.is_err() {
        return 1
    }
    if select_send_metrics.unwrap().select_attempts != 3 {
        return 1
    }
    if select_send_metrics.unwrap().select_default_fallbacks != 0 {
        return 1
    }
    if select_send_metrics.unwrap().select_timeouts != 0 {
        return 1
    }
    if select_send_metrics.unwrap().channel_sends != 3 {
        return 1
    }

    var select_syntax_src = "package demo.selectsyntax\nfunc main() int {\n  var ch1 = chan_make(1)\n  var ch2 = chan_make(1)\n  chan_send(ch1, 5)\n  chan_send(ch2, 7)\n  println(select {\n    case recv(ch1, ch2):\n  })\n  select {\n    case recv(ch1, ch2):\n    case timeout(3):\n  }\n  select {\n    case send(ch1, 8, ch2, 9):\n    case default:\n  }\n  println(chan_recv(ch1))\n  chan_close(ch1)\n  chan_close(ch2)\n  0\n}"
    var select_syntax_parsed = parse_source(select_syntax_src)
    if select_syntax_parsed.is_err() {
        return 1
    }
    var select_syntax_graph = lower_main_to_mir(select_syntax_parsed.unwrap())
    if select_syntax_graph.is_err() {
        return 1
    }
    var select_syntax_writes = compile_writes(select_syntax_parsed.unwrap(), select_syntax_graph.unwrap())
    if select_syntax_writes.is_err() {
        return 1
    }
    if select_syntax_writes.unwrap().len() != 2 {
        return 1
    }
    if select_syntax_writes.unwrap()[0].text != "5\n" {
        return 1
    }
    if select_syntax_writes.unwrap()[1].text != "8\n" {
        return 1
    }
    var select_syntax_metrics = compile_runtime_metrics(select_syntax_parsed.unwrap(), select_syntax_graph.unwrap())
    if select_syntax_metrics.is_err() {
        return 1
    }
    if select_syntax_metrics.unwrap().select_attempts != 3 {
        return 1
    }
    if select_syntax_metrics.unwrap().select_timeouts != 1 {
        return 1
    }
    if select_syntax_metrics.unwrap().select_default_fallbacks != 0 {
        return 1
    }

    var sroutine_recover_src = "package demo.srrecover\nfunc recover_worker() int {\n  recover()\n  println(\"recover-ok\")\n  0\n}\nfunc worker() int {\n  defer recover_worker()\n  println(msg)\n  panic(\"boom\")\n  0\n}\nfunc main() int {\n  var msg = \"captured\"\n  sroutine worker()\n  println(\"main\")\n  0\n}"
    var sroutine_recover_parsed = parse_source(sroutine_recover_src)
    if sroutine_recover_parsed.is_err() {
        return 1
    }
    var sroutine_recover_graph = lower_main_to_mir(sroutine_recover_parsed.unwrap())
    if sroutine_recover_graph.is_err() {
        return 1
    }
    var sroutine_recover_writes = compile_writes(sroutine_recover_parsed.unwrap(), sroutine_recover_graph.unwrap())
    if sroutine_recover_writes.is_err() {
        return 1
    }
    if sroutine_recover_writes.unwrap().len() != 3 {
        return 1
    }
    if sroutine_recover_writes.unwrap()[0].text != "captured\n" {
        return 1
    }
    if sroutine_recover_writes.unwrap()[1].text != "recover-ok\n" {
        return 1
    }
    if sroutine_recover_writes.unwrap()[2].text != "main\n" {
        return 1
    }

    var const_iota_src = "package demo.consts\nconst (\n  A = iota\n  B\n)\nconst C = 10 / B\nfunc main() int {\n  println(C)\n  0\n}"
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

    var const_iota_fail_src = "package demo.consts\nconst (\n  A = iota\n  B = 10 / A\n)\nfunc main() int {\n  0\n}"
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

func contains_all(string text, vec[string] needles) bool {
    var i = 0
    while i < needles.len() {
        if !contains(text, needles[i]) {
            return false
        }
        i = i + 1
    }
    true
}

func read_artifact_or_empty(string path) string {
    var content = read_to_string(path)
    if content.is_err() {
        return ""
    }
    content.unwrap()
}

func require_artifact_markers(string path, vec[string] markers) string {
    var content = read_artifact_or_empty(path)
    if content == "" {
        return ""
    }
    if !contains_all(content, markers) {
        return ""
    }
    content
}

func validate_emitted_artifacts(string out_path) bool {
    var opt = require_artifact_markers(out_path + ".opt", vec[string]("midend-opt version=1", "scheduler_opt sroutine_sites=1", "select_timeout_sites=1", "select_send_sites=1"))
    if opt == "" || validate_midend_opt_artifact(opt).is_err() {
        return false
    }

    var perf = require_artifact_markers(out_path + ".perf", vec[string]("perf-baseline version=1", "scheduler queue_policy=priority-rr select_policy=multi-chan-priority-rr", "select_timeout_sites=1", "select_send_sites=1", "scheduler_counters", "runtime_sched sroutine_scheduled=1", "runtime_gc cycles=", "heap_goal="))
    if perf == "" || validate_backend_perf_baseline(perf).is_err() {
        return false
    }

    var toolchain = require_artifact_markers(out_path + ".toolchain", vec[string]("toolchain-compat version=1", "asm=go-plan9-min", "go_asm syntax=plan9 translator=enabled status=ok"))
    if toolchain == "" || validate_toolchain_compat_artifact(toolchain).is_err() {
        return false
    }

    if require_artifact_markers(out_path + ".gcmap", vec[string]("gcmap version=1", "collector plan=go-like-mark-sweep", "safepoints=alloc-trigger", "ptr_bitmap=", "contract e2e_safepoint=")) == "" {
        return false
    }

    var cfi = require_artifact_markers(out_path + ".cfi", vec[string]("cfi version=1", ".cfi_startproc", ".cfi_def_cfa", ".cfi_endproc"))
    if cfi == "" || validate_cfi_artifact(cfi).is_err() {
        return false
    }

    var dwarf = require_artifact_markers(out_path + ".dwarf", vec[string]("section .debug_info", "section .debug_line", "section .debug_loc", "section .debug_ranges", "policy debug_budget_mode=", "metric location_continuity="))
    if dwarf == "" || validate_dwarf_consumability(dwarf, "ssa dbg_budget=30").is_err() {
        return false
    }

    if require_artifact_markers(out_path + ".stackmap", vec[string]("stackmap version=1", "fn main slots=", "bitmap=", "callee_saved=")) == "" {
        return false
    }
    if require_artifact_markers(out_path + ".abi", vec[string]("abi version=1", "fn main params=0", "pass=", "ret=", "abi_in_regs=", "abi_summary=")) == "" {
        return false
    }
    if require_artifact_markers(out_path + ".abi.emit", vec[string]("abi-emit version=1", "fn main", "ret_arity=1", "callseq=", "abi_in_regs=")) == "" {
        return false
    }
    if require_artifact_markers(out_path + ".export", vec[string]("export-data version=1", "fn worker params=0 generics=0", "fn main params=0 generics=0")) == "" {
        return false
    }
    if require_artifact_markers(out_path + ".abi.matrix", vec[string]("abi-matrix version=1", "axis caller_saved=", "matrix callseq=", "cross_arch_consistency=")) == "" {
        return false
    }
    if require_artifact_markers(out_path + ".dbg", vec[string]("ssa\n", "\n\ndebug\n", "value#", "dbg_lines=")) == "" {
        return false
    }

    true
}
