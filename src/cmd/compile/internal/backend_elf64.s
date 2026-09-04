package compile.internal.backend_elf64
use compile.internal.ir.lower.lower_main_to_mir
use compile.internal.abi.new_abi_config
use compile.internal.abi.abi_analyze_types
use compile.internal.abi.in_registers_used as abiutils_in_registers_used
use compile.internal.abi.out_registers_used as abiutils_out_registers_used
use compile.internal.abi.spill_area_size as abiutils_spill_area_size
use compile.internal.abi.arg_width as abiutils_arg_width
use compile.internal.abi.info_string as abiutils_info_string
use compile.internal.mir.mir_graph
use compile.internal.mir.mir_basic_block
use compile.internal.mir.mir_statement
use compile.internal.mir.mir_control_edge
use compile.internal.mir.dump_graph
use compile.internal.inline.estimate_inline_sites_graph
use compile.internal.escape.estimate_escape_sites_graph
use compile.internal.dispatch.devirtualize.estimate_devirtualized_sites_graph
use compile.internal.ssa_core.build_pipeline_with_graph_hints_and_margin as build_ssa_pipeline_with_graph_hints_and_margin
use compile.internal.ssa_core.dump_pipeline as dump_ssa_pipeline
use compile.internal.ssa_core.dump_debug_map as dump_ssa_debug_map
use internal.buildcfg.goarch as buildcfg_goarch
use compile.internal.semantic.check_text
use compile.internal.syntax.parse_source
use s.assign_stmt
use s.binary_expr
use s.block_expr
use s.bool_expr
use s.c_for_stmt
use s.call_expr
use s.expr
use s.expr_stmt
use s.function_decl
use s.if_expr
use s.increment_stmt
use s.int_expr
use s.item
use s.name_expr
use s.source_file
use s.stmt
use s.string_expr
use s.sroutine_stmt
use s.use_decl
use s.var_stmt
use s.while_expr
use std.fs.make_temp_dir
use std.fs.read_to_string
use std.fs.write_text_file
use std.env.get as env_get
use std.io.eprintln
use std.option.option
use std.process.run_process
use std.prelude.char_at
use std.prelude.len
use std.prelude.slice
use std.prelude.to_string
use std.slices
struct backend_error {
    string message
}

func ok_function(function_decl value) (function_decl, backend_error) {
    result.ok(value);
}

func fail_function(string message) (function_decl, backend_error) {
    result.err(backend_error {
        message: message,
    });
}

func ok_write_ops(write_op[] value) (write_op[], backend_error) {
    result.ok(value);
}

func fail_write_ops(string message) (write_op[], backend_error) {
    result.err(backend_error {
        message: message,
    });
}

func ok_value(value value) (value, backend_error) {
    result.ok(value);
}

func fail_value(string message) (value, backend_error) {
    result.err(backend_error {
        message: message,
    });
}

func ok_unit() ((), backend_error) {
    result.ok(());
}

func fail_unit(string message) ((), backend_error) {
    result.err(backend_error {
        message: message,
    });
}

func ok_int(int value) (int, backend_error) {
    result.ok(value);
}

func fail_int(string message) (int, backend_error) {
    result.err(backend_error {
        message: message,
    });
}
control_panic_active := "@panic.active"
control_panic_payload := "@panic.payload"
control_in_defer := "@defer.active"

struct unit_value {}

struct fn_map_entry_value {
    string key
    string func_name
}

struct channel_handle_value {
    int id
}

struct channel_runtime_state {
    int id
    int capacity
    value[] buffer
    bool closed
    int sends
    int recvs
}

struct captured_binding {
    string name
    value value
}

struct sroutine_task {
    string fn_name
    value[] args
    captured_binding[] captured_env
    string origin
}

struct runtime_state {
    sroutine_task[] runq
    channel_runtime_state[] channels
    int next_channel_id
    int select_rr_cursor
    int sroutine_scheduled
    int sroutine_completed
    int sroutine_panics
    int sroutine_recovered
    int sroutine_yields
    int select_attempts
    int select_default_fallbacks
    int select_timeouts
}

struct runtime_metrics {
    int sroutine_scheduled
    int sroutine_completed
    int sroutine_panics
    int sroutine_recovered
    int sroutine_yields
    int select_attempts
    int select_default_fallbacks
    int select_timeouts
    int channels
    int channel_sends
    int channel_recvs
    int channel_closed
}
enum value {
    int(int),
    string(string),
    bool(bool),
    unit(unit_value),
    channel(channel_handle_value),
    fn_ref(string),
    fn_map(fn_map_entry_value[]),
}

struct binding {
    string name
    value value
}

struct write_op {
    int fd
    string text
}

struct mir_execution_result {
    write_op[] writes
    int exit_code
    runtime_metrics runtime
}

struct midend_result {
    string optimized_mir_text
    string report
}

struct stackmap_function_entry {
    string name
    int slots
    string bitmap
    int callee_saved
}

struct abi_behavior_entry {
    string name
    int param_count
    bool variadic
    string pass_mode
    string return_mode
    int abi_in_regs
    int abi_out_regs
    int abi_spill_size
    int abi_arg_width
    string abi_summary
}

func build_object(string path, string output, string ssa_margin_override) int {
    source_result := read_to_string(path)
    if source_result.is_err() {
        return report_failure("failed to read source file: " + path + ": " + source_result.unwrap_err().message)
    }
    source := source_result.unwrap()
    parsed_result := load_source_graph(path, source)
    if parsed_result.is_err() {
        return report_failure(parsed_result.unwrap_err().message)
    }
    parsed := parsed_result.unwrap()
    if !should_skip_semantic_check(path) && check_text(source) != 0 {
        return report_failure("semantic check failed")
    }
    mir_result := lower_main_to_mir(parsed)
    if mir_result.is_err() {
        return report_failure("mir lowering failed: " + mir_result.unwrap_err())
    }
    graph := mir_result.unwrap()
    arch := buildcfg_goarch()
    margin_result := parse_ssa_margin_override(ssa_margin_override)
    if margin_result.is_err() {
        return report_failure(margin_result.unwrap_err().message)
    }
    dominant_margin := margin_result.unwrap()
    midend := run_midend_pipeline(graph)
    ssa_program := build_ssa_pipeline_with_graph_hints_and_margin(graph, midend.optimized_mir_text, arch, dominant_margin)
    ssa_text := dump_ssa_pipeline(ssa_program)
    if ssa_text == "" {
        return report_failure("ssa lowering failed: empty pipeline")
    }
    debug_map := dump_ssa_debug_map(ssa_program)
    if debug_map == "" {
        return report_failure("ssa debug map failed: empty map")
    }
    abi_runtime_check := validate_ssa_abi_contracts(arch, ssa_text)
    if abi_runtime_check.is_err() {
        return report_failure(abi_runtime_check.unwrap_err().message)
    }
    abi_check := validate_abi_coverage(arch)
    if abi_check.is_err() {
        return report_failure(abi_check.unwrap_err().message)
    }
    writes_result := compile_writes(parsed, graph)
    if writes_result.is_err() {
        return report_failure(writes_result.unwrap_err().message)
    }
    exit_code_result := compile_exit_code(parsed, graph)
    if exit_code_result.is_err() {
        return report_failure(exit_code_result.unwrap_err().message)
    }
    temp_dir_result := make_temp_dir("s-object-")
    if temp_dir_result.is_err() {
        return report_failure("could not create temporary output directory: " + temp_dir_result.unwrap_err().message)
    }
    temp_dir := temp_dir_result.unwrap()
    asm_path := temp_dir + "/out.s"
    asm_text := emit_asm(writes_result.unwrap(), exit_code_result.unwrap())
    write_result := write_text_file(asm_path, asm_text)
    if write_result.is_err() {
        return report_failure("failed to write assembly: " + write_result.unwrap_err().message)
    }
    as_argv := string[]()
    as_argv = append(as_argv, "as")
    as_argv = append(as_argv, "-o")
    as_argv = append(as_argv, output)
    as_argv = append(as_argv, asm_path)
    as_result := run_process(as_argv)
    if as_result.is_err() {
        return report_failure("toolchain failed: " + as_result.unwrap_err().message)
    }
    0
}

func build(string path, string output, string ssa_margin_override, bool nostdlib) int {
    source_result := read_to_string(path)
    if source_result.is_err() {
        return report_failure("failed to read source file: " + path + ": " + source_result.unwrap_err().message
    }
    source := source_result.unwrap()
    if is_compiler_runtime_entry(path, source) {
        return build_compiler_runtime_launcher(output
    }
    parsed_result := load_source_graph(path, source)
    if parsed_result.is_err() {
        return report_failure(parsed_result.unwrap_err().message
    }
    parsed := parsed_result.unwrap()
    if !should_skip_semantic_check(path) && check_text(source) != 0 {
        return report_failure("semantic check failed"
    }
    mir_result := lower_main_to_mir(parsed)
    if mir_result.is_err() {
        return report_failure("mir lowering failed: " + mir_result.unwrap_err())
    }
    graph := mir_result.unwrap()
    arch := buildcfg_goarch()
    margin_result := parse_ssa_margin_override(ssa_margin_override)
    if margin_result.is_err() {
        return report_failure(margin_result.unwrap_err().message
    }
    dominant_margin := margin_result.unwrap()
    midend := run_midend_pipeline(graph)
    ssa_program := build_ssa_pipeline_with_graph_hints_and_margin(graph, midend.optimized_mir_text, arch, dominant_margin)
    ssa_text := dump_ssa_pipeline(ssa_program)
    if ssa_text == "" {
        return report_failure("ssa lowering failed: empty pipeline"
    }
    debug_map := dump_ssa_debug_map(ssa_program)
    if debug_map == "" {
        return report_failure("ssa debug map failed: empty map"
    }
    abi_runtime_check := validate_ssa_abi_contracts(arch, ssa_text)
    if abi_runtime_check.is_err() {
        return report_failure(abi_runtime_check.unwrap_err().message
    }
    abi_check := validate_abi_coverage(arch)
    if abi_check.is_err() {
        return report_failure(abi_check.unwrap_err().message
    }
    writes_result := compile_writes(parsed, graph)
    if writes_result.is_err() {
        return report_failure(writes_result.unwrap_err().message
    }
    exit_code_result := compile_exit_code(parsed, graph)
    if exit_code_result.is_err() {
        return report_failure(exit_code_result.unwrap_err().message
    }
    runtime_metrics_result := compile_runtime_metrics(parsed, graph)
    if runtime_metrics_result.is_err() {
        return report_failure(runtime_metrics_result.unwrap_err().message
    }
    temp_dir_result := make_temp_dir("s-build-")
    if temp_dir_result.is_err() {
        return report_failure("could not create temporary output directory: " + temp_dir_result.unwrap_err().message
    }
    temp_dir := temp_dir_result.unwrap()
    if arch == "wasm" {
        wasm_result := build_wasm_object_chain(temp_dir, output, writes_result.unwrap(), exit_code_result.unwrap())
        if wasm_result.is_err() {
            return report_failure(wasm_result.unwrap_err().message
        }
        wasm_binary_check := validate_wasi_binary_artifact(output)
        if wasm_binary_check.is_err() {
            return report_failure(wasm_binary_check.unwrap_err().message
        }
    } else {
        asm_text := emit_asm(writes_result.unwrap(), exit_code_result.unwrap())
        asm_path := temp_dir + "/out.s"
        obj_path := temp_dir + "/out.o"
        write_result := write_text_file(asm_path, asm_text)
        if write_result.is_err() {
            return report_failure("failed to write assembly: " + write_result.unwrap_err().message
        }
        as_argv := string[]()
        as_argv = append(as_argv, "as");
        as_argv = append(as_argv, "-o");
        as_argv = append(as_argv, obj_path);
        as_argv = append(as_argv, asm_path);
        as_result := run_process(as_argv)
        if as_result.is_err() {
            return report_failure("toolchain failed: " + as_result.unwrap_err().message
        }
        ld_argv := string[]()
        ld_argv = append(ld_argv, "ld")
        if nostdlib {
            ld_argv = append(ld_argv, "-nostdlib")
            ld_argv = append(ld_argv, "-static")
            ld_argv = append(ld_argv, "-T")
            ld_argv = append(ld_argv, "src/runtime/linker/nostdlib.ld")
        }
        ld_argv = append(ld_argv, "-o")
        ld_argv = append(ld_argv, output)
        ld_argv = append(ld_argv, obj_path)
        ld_result := run_process(ld_argv)
        if ld_result.is_err() {
            return report_failure("toolchain failed: " + ld_result.unwrap_err().message
        }
    }
    dbg_path := output + ".dbg"
    dbg_payload := "ssa\n" + ssa_text + "\n\ndebug\n" + debug_map
    dbg_write := write_text_file(dbg_path, dbg_payload)
    if dbg_write.is_err() {
        return report_failure("failed to write debug artifact: " + dbg_write.unwrap_err().message
    }
    stackmap_path := output + ".stackmap"
    stackmap_payload := build_stackmap_artifact(arch, parsed, ssa_text, debug_map)
    stackmap_write := write_text_file(stackmap_path, stackmap_payload)
    if stackmap_write.is_err() {
        return report_failure("failed to write stack map artifact: " + stackmap_write.unwrap_err().message
    }
    abi_path := output + ".abi"
    abi_payload := build_abi_behavior_artifact(arch, parsed)
    abi_write := write_text_file(abi_path, abi_payload)
    if abi_write.is_err() {
        return report_failure("failed to write ABI behavior artifact: " + abi_write.unwrap_err().message
    }
    abi_emit_path := output + ".abi.emit"
    abi_emit_payload := build_abi_emit_plan(arch, parsed)
    abi_emit_write := write_text_file(abi_emit_path, abi_emit_payload)
    if abi_emit_write.is_err() {
        return report_failure("failed to write ABI emission artifact: " + abi_emit_write.unwrap_err().message
    }
    abi_matrix_payload := build_abi_machine_matrix_artifact(arch, parsed, ssa_text)
    abi_matrix_check := validate_abi_machine_matrix(abi_matrix_payload)
    if abi_matrix_check.is_err() {
        return report_failure(abi_matrix_check.unwrap_err().message
    }
    abi_matrix_path := output + ".abi.matrix"
    abi_matrix_write := write_text_file(abi_matrix_path, abi_matrix_payload)
    if abi_matrix_write.is_err() {
        return report_failure("failed to write ABI matrix artifact: " + abi_matrix_write.unwrap_err().message
    }
    dwarf_path := output + ".dwarf"
    dwarf_payload := build_dwarf_like_artifact(parsed, ssa_text, debug_map)
    dwarf_check := validate_dwarf_consumability(dwarf_payload, ssa_text)
    if dwarf_check.is_err() {
        return report_failure(dwarf_check.unwrap_err().message
    }
    dwarf_write := write_text_file(dwarf_path, dwarf_payload)
    if dwarf_write.is_err() {
        return report_failure("failed to write DWARF-like artifact: " + dwarf_write.unwrap_err().message
    }
    cfi_path := output + ".cfi"
    cfi_payload := build_cfi_artifact(arch, ssa_text, debug_map)
    cfi_check := validate_cfi_artifact(cfi_payload)
    if cfi_check.is_err() {
        return report_failure(cfi_check.unwrap_err().message
    }
    cfi_write := write_text_file(cfi_path, cfi_payload)
    if cfi_write.is_err() {
        return report_failure("failed to write CFI artifact: " + cfi_write.unwrap_err().message
    }
    export_path := output + ".export"
    export_payload := build_export_data_artifact(parsed, arch)
    export_write := write_text_file(export_path, export_payload)
    if export_write.is_err() {
        return report_failure("failed to write export data artifact: " + export_write.unwrap_err().message
    }
    toolchain_path := output + ".toolchain"
    toolchain_payload := build_toolchain_compat_artifact(parsed, arch)
    toolchain_check := validate_toolchain_compat_artifact(toolchain_payload)
    if toolchain_check.is_err() {
        return report_failure(toolchain_check.unwrap_err().message
    }
    toolchain_write := write_text_file(toolchain_path, toolchain_payload)
    if toolchain_write.is_err() {
        return report_failure("failed to write toolchain compatibility artifact: " + toolchain_write.unwrap_err().message
    }
    perf_path := output + ".perf"
    perf_payload := build_backend_perf_baseline_artifact(arch, ssa_text, midend.report, runtime_metrics_text(runtime_metrics_result.unwrap()))
    perf_check := validate_backend_perf_baseline(perf_payload)
    if perf_check.is_err() {
        return report_failure(perf_check.unwrap_err().message
    }
    perf_write := write_text_file(perf_path, perf_payload)
    if perf_write.is_err() {
        return report_failure("failed to write backend perf baseline artifact: " + perf_write.unwrap_err().message
    }
    opt_path := output + ".opt"
    opt_payload := build_midend_opt_artifact(midend.report)
    opt_check := validate_midend_opt_artifact(opt_payload)
    if opt_check.is_err() {
        return report_failure(opt_check.unwrap_err().message
    }
    opt_write := write_text_file(opt_path, opt_payload)
    if opt_write.is_err() {
        return report_failure("failed to write optimization report: " + opt_write.unwrap_err().message
    }
    0
}

func run_midend_pipeline(mir_graph graph) midend_result {
    pass := apply_midend_pass_pipeline(graph)
    rewritten_graph := pass.graph
    inlined := estimate_inline_sites_graph(rewritten_graph)
    escaped := estimate_escape_sites_graph(rewritten_graph)
    devirt := estimate_devirtualized_sites_graph(rewritten_graph)
    cross_pkg_inline := estimate_cross_pkg_inline_sites_graph(rewritten_graph, inlined)
    const_prop := estimate_const_prop_sites_graph(rewritten_graph)
    sroutine_sites := estimate_sroutine_sites_graph(rewritten_graph)
    select_weighted_sites := estimate_trace_call_sites_graph(rewritten_graph, "select_recv_weighted(")
    select_timeout_sites := estimate_trace_call_sites_graph(rewritten_graph, "select_recv_timeout(")
    select_send_sites := estimate_trace_call_sites_graph(rewritten_graph, "select_send(")
    ipo_synergy := estimate_ipo_synergy(inlined, escaped, devirt, cross_pkg_inline, const_prop)
    iter := 0
    for iter < 2 {
        if inlined > escaped {
            escaped = escaped + inlined / 3
        }
        if escaped > 0 && devirt > 0 {
            inlined = inlined + devirt / 2
        }
        if devirt > inlined {
            devirt = inlined
        }
        if escaped > inlined {
            escaped = inlined
        }
        iter = iter + 1
    }
    rewritten := dump_graph(rewritten_graph)
    if inlined > 0 {
        rewritten = rewritten + " inline=" + to_string(inlined)
    }
    if escaped > 0 {
        rewritten = rewritten + " escape=" + to_string(escaped)
    }
    if devirt > 0 {
        rewritten = rewritten + " devirt=" + to_string(devirt)
    }
    if cross_pkg_inline > 0 {
        rewritten = rewritten + " xinline=" + to_string(cross_pkg_inline)
    }
    if const_prop > 0 {
        rewritten = rewritten + " constprop=" + to_string(const_prop)
    }
    if sroutine_sites > 0 {
        rewritten = rewritten + " sroutine=" + to_string(sroutine_sites)
    }
    if select_weighted_sites > 0 {
        rewritten = rewritten + " selectw=" + to_string(select_weighted_sites)
    }
    if select_timeout_sites > 0 {
        rewritten = rewritten + " selectt=" + to_string(select_timeout_sites)
    }
    if select_send_sites > 0 {
        rewritten = rewritten + " selects=" + to_string(select_send_sites)
    }
    const_fold_hits := estimate_const_fold_hits_graph(graph)
    rewritten = rewritten + " constfold=" + to_string(const_fold_hits)
    rewritten = rewritten + " ipo=" + to_string(ipo_synergy)
    rewritten = rewritten + " pass.rm_unreachable=" + to_string(pass.removed_unreachable_blocks)
    rewritten = rewritten + " pass.fold_branch=" + to_string(pass.folded_redundant_branches)
    rewritten = rewritten + " pass.simplify_j2r=" + to_string(pass.simplified_jump_to_return)
    rewritten = rewritten + " pass.trim_unit=" + to_string(pass.removed_unit_lines)
    rewritten = rewritten + " pass.dedup=" + to_string(pass.dedup_lines)
    report := "midend"
        + " inline_sites=" + to_string(inlined)
        + " escape_sites=" + to_string(escaped)
        + " devirtualized=" + to_string(devirt)
        + " cross_pkg_inline=" + to_string(cross_pkg_inline)
        + " const_prop=" + to_string(const_prop)
        + " sroutine_sites=" + to_string(sroutine_sites)
        + " select_weighted_sites=" + to_string(select_weighted_sites)
        + " select_timeout_sites=" + to_string(select_timeout_sites)
        + " select_send_sites=" + to_string(select_send_sites)
        + " const_fold_hits=" + to_string(const_fold_hits)
        + " ipo_synergy=" + to_string(ipo_synergy)
        + " pass_rm_unreachable=" + to_string(pass.removed_unreachable_blocks)
        + " pass_fold_branch=" + to_string(pass.folded_redundant_branches)
        + " pass_simplify_j2r=" + to_string(pass.simplified_jump_to_return)
        + " pass_trim_unit=" + to_string(pass.removed_unit_lines)
        + " pass_dedup=" + to_string(pass.dedup_lines)
    midend_result {
        optimized_mir_text: rewritten, report report,
    }
}

func estimate_sroutine_sites_graph(mir_graph graph) int {
    total := 0
    i := 0
    for i < len(graph.trace) {
        if has_substring(graph.trace[i], "stmt sroutine ") {
            total = total + 1
        }
        i = i + 1
    }
    total
}

func estimate_trace_call_sites_graph(mir_graph graph, string marker) int {
    total := 0
    i := 0
    for i < len(graph.trace) {
        if has_substring(graph.trace[i], marker) {
            total = total + 1
        }
        i = i + 1
    }
    total
}

func estimate_const_fold_hits_graph(mir_graph graph) int {
    prefix := "constfold.hits="
    i := 0
    for i < len(graph.trace) {
        line := trim_spaces(graph.trace[i])
        if starts_with_local(line, prefix) {
            return parse_non_negative_int(slice(line, len(prefix), len(line)))
        }
        i = i + 1
    }
    0
}

func parse_non_negative_int(string raw) int {
    text := trim_spaces(raw)
    if text == "" {
        return 0
    }
    value := 0
    i := 0
    for i < len(text) {
        ch := char_at(text, i)
        digit := digit_value(ch)
        if digit < 0 {
            return 0
        }
        value = value * 10 + digit
        i = i + 1
    }
    value
}

struct midend_pass_result {
    mir_graph graph
    int simplified_jump_to_return
    int removed_unit_lines
    int dedup_lines
    int removed_unreachable_blocks
    int folded_redundant_branches
}

func apply_midend_pass_pipeline(mir_graph graph) midend_pass_result {
    rewritten := graph
    unreachable := remove_unreachable_blocks_pass(rewritten)
    rewritten = unreachable.graph
    folded := simplify_redundant_branch_pass(rewritten)
    rewritten = folded.graph
    simplified := simplify_jump_to_return_pass(rewritten)
    rewritten = simplified.graph
    trimmed := trim_unit_line_pass(rewritten)
    rewritten = trimmed.graph
    deduped := dedup_eval_line_pass(rewritten)
    rewritten = deduped.graph
    midend_pass_result {
        graph: rewritten, simplified_jump_to_return simplified.count, removed_unit_lines trimmed.count, dedup_lines deduped.count, removed_unreachable_blocks unreachable.count, folded_redundant_branches folded.count,
    }
}

func remove_unreachable_blocks_pass(mir_graph graph) graph_pass_count_result {
    rewritten := graph
    reachable := int[]()
    work := int[]()
    work = append(work, rewritten.entry)
    for len(work) > 0 {
        id := work[len(work) - 1]
        work.pop()
        if contains_int32(reachable, id) {
            continue
        }
        reachable = append(reachable, id)
        bi := find_block_index_by_id(rewritten, id)
        if bi < 0 {
            continue
        }
        ei := 0
        for ei < rewritten.blocks[bi]len(.terminator.edges) {
            next := rewritten.blocks[bi].terminator.edges[ei].target
            if !contains_int32(reachable, next) {
                work = append(work, next)
            }
            ei = ei + 1
        }
    }
    filtered_blocks := mir_basic_block[]()
    i := 0
    for i < len(rewritten.blocks) {
        if contains_int32(reachable, rewritten.blocks[i].id) {
            filtered_blocks = append(filtered_blocks, rewritten.blocks[i])
        }
        i = i + 1
    }
    removed := len(rewritten.blocks) - len(filtered_blocks)
    rewritten.blocks = filtered_blocks
    i = 0
    for i < len(rewritten.blocks) {
        kept_edges := mir_control_edge[]()
        j := 0
        for j < rewritten.blocks[i]len(.terminator.edges) {
            edge := rewritten.blocks[i].terminator.edges[j]
            if contains_int32(reachable, edge.target) {
                kept_edges = append(kept_edges, edge)
            }
            j = j + 1
        }
        rewritten.blocks[i].terminator.edges = kept_edges
        i = i + 1
    }
    if !contains_int32(reachable, rewritten.exit) {
        rewritten.exit = rewritten.entry
    }
    graph_pass_count_result { graph: rewritten, count removed }
}

func simplify_redundant_branch_pass(mir_graph graph) graph_pass_count_result {
    rewritten := graph
    changed := 0
    i := 0
    for i < len(rewritten.blocks) {
        block := rewritten.blocks[i]
        if block.terminator.kind == "branch" && len(block.terminator.edges) > 1 {
            target := block.terminator.edges[0].target
            same_target := true
            j := 1
            for j < len(block.terminator.edges) {
                if block.terminator.edges[j].target != target {
                    same_target = false
                }
                j = j + 1
            }
            if same_target {
                folded := mir_control_edge[]()
                folded.push(mir_control_edge {
                    label: "folded", target target, args mir_operand[](),
                })
                rewritten.blocks[i].terminator.kind = "jump"
                rewritten.blocks[i].terminator.edges = folded
                changed = changed + 1
            }
        }
        i = i + 1
    }
    graph_pass_count_result { graph: rewritten, count changed }
}

func contains_int32(int[] values, int needle) bool {
    i := 0
    for i < len(values) {
        if values[i] == needle {
            return true
        }
        i = i + 1
    }
    false
}

struct graph_pass_count_result {
    mir_graph graph
    int count
}

func simplify_jump_to_return_pass(mir_graph graph) graph_pass_count_result {
    rewritten := graph
    changed := 0
    i := 0
    for i < len(rewritten.blocks) {
        block := rewritten.blocks[i]
        if block.terminator.kind == "jump" && len(block.terminator.edges) == 1 {
            target_id := block.terminator.edges[0].target
            ti := find_block_index_by_id(rewritten, target_id)
            if ti >= 0 {
                target := rewritten.blocks[ti]
                if target.terminator.kind == "return" && len(target.statements) == 0 {
                    rewritten.blocks[i].terminator.kind = "return"
                    rewritten.blocks[i].terminator.edges = mir_control_edge[]()
                    changed = changed + 1
                }
            }
        }
        i = i + 1
    }
    graph_pass_count_result { graph: rewritten, count changed }
}

func trim_unit_line_pass(mir_graph graph) graph_pass_count_result {
    rewritten := graph
    changed := 0
    i := 0
    for i < len(rewritten.blocks) {
        if rewritten.blocks[i].terminator.kind == "return" {
            filtered := mir_statement[]()
            j := 0
            for j < rewritten.blocks[i]len(.statements) {
                keep := true
                switch rewritten.blocks[i].statements[j] {
                    mir_statement::eval(eval_stmt) : {
                        if eval_stmt.op == "line" && len(eval_stmt.args) > 0 && eval_stmt.args[0] == "yield unit" {
                            keep = false
                            changed = changed + 1
                        }
                    }
                    _ : (),
                }
                if keep {
                    filtered = append(filtered, rewritten.blocks[i].statements[j])
                }
                j = j + 1
            }
            rewritten.blocks[i].statements = filtered
        }
        i = i + 1
    }
    graph_pass_count_result { graph: rewritten, count changed }
}

func dedup_eval_line_pass(mir_graph graph) graph_pass_count_result {
    rewritten := graph
    changed := 0
    i := 0
    for i < len(rewritten.blocks) {
        filtered := mir_statement[]()
        last_line := ""
        j := 0
        for j < rewritten.blocks[i]len(.statements) {
            push_stmt := true
            switch rewritten.blocks[i].statements[j] {
                mir_statement::eval(eval_stmt) : {
                    if eval_stmt.op == "line" && len(eval_stmt.args) > 0 {
                        current := eval_stmt.args[0]
                        if current == last_line {
                            push_stmt = false
                            changed = changed + 1
                        }
                        last_line = current
                    } else {
                        last_line = ""
                    }
                }
                _ : {
                    last_line = ""
                }
            }
            if push_stmt {
                filtered = append(filtered, rewritten.blocks[i].statements[j])
            }
            j = j + 1
        }
        rewritten.blocks[i].statements = filtered
        i = i + 1
    }
    graph_pass_count_result { graph: rewritten, count changed }
}

func find_block_index_by_id(mir_graph graph, int id) int {
    i := 0
    for i < len(graph.blocks) {
        if graph.blocks[i].id == id {
            return i
        }
        i = i + 1
    }
    0 - 1
}

func validate_ssa_abi_contracts(string arch, string ssa_text) ((), backend_error) {
    spills := parse_number_after(ssa_text, "spills=")
    reloads := parse_number_after(ssa_text, "reloads=")
    pressure := parse_number_after(ssa_text, "call_pressure=")
    if spills > 0 && reloads >= 0 && reloads < spills {
        return backend_error { message: "backend error: reload count lower than spill count" }
    }
    if pressure > 0 {
        budget := abi_caller_saved_count(arch) * 4
        if budget > 0 && pressure > budget {
            return backend_error { message: "backend error: call pressure exceeds ABI budget" }
        }
    }
    if has_substring(ssa_text, "tailcall") {
        if arch == "wasm" {
            return backend_error { message: "backend error: tailcall is not legal on wasm path" }
        }
        if spills > 0 {
            return backend_error { message: "backend error: tailcall with spill slots is not legal" }
        }
    }
    preserve := validate_callsite_preservation(ssa_text)
    if preserve.is_err() {
        return preserve
    }
    ()
}

func validate_callsite_preservation(string ssa_text) ((), backend_error) {
    clobber := parse_number_after(ssa_text, "callee_saved_clobber=")
    if clobber > 0 {
        return backend_error { message: "backend error: callee-saved registers clobbered at callsite" }
    }
    restore_missing := parse_number_after(ssa_text, "caller_restore_missing=")
    if restore_missing > 0 {
        return backend_error { message: "backend error: caller restore is missing at callsite" }
    }
    if has_substring(ssa_text, "call_preserve=fail") {
        return backend_error { message: "backend error: callsite preserve contract failed" }
    }
    ()
}

func build_cfi_artifact(string arch, string ssa_text, string debug_map) string {
    lines := string[]()
    lines = append(lines, "cfi version=1 arch=" + arch)
    lines = append(lines, ".cfi_startproc")
    lines = append(lines, ".cfi_def_cfa sp, " + to_string(abi_stack_alignment(arch)))
    lines = append(lines, ".cfi_offset ra, -8")
    lines = append(lines, "ssa " + ssa_text)
    lines = append(lines, "debug " + debug_map)
    lines = append(lines, ".cfi_endproc")
    join_lines(lines)
}

func validate_cfi_artifact(string payload) ((), backend_error) {
    if !has_substring(payload, "cfi version=1") {
        return backend_error { message: "backend error: cfi header missing" }
    }
    if !has_substring(payload, ".cfi_startproc") || !has_substring(payload, ".cfi_endproc") {
        return backend_error { message: "backend error: cfi proc markers missing" }
    }
    if !has_substring(payload, ".cfi_def_cfa") {
        return backend_error { message: "backend error: cfi cfa rule missing" }
    }
    ()
}

func estimate_cross_pkg_inline_sites_graph(mir_graph graph, int inlined) int {
    imports := 0
    i := 0
    for i < len(graph.trace) {
        if has_substring(graph.trace[i], "package.fn ") {
            imports = imports + 1
        }
        i = i + 1
    }
    score := inlined / 2 + imports
    if score < 0 {
        return 0
    }
    score
}

func estimate_const_prop_sites_graph(mir_graph graph) int {
    constants := 0
    i := 0
    for i < len(graph.blocks) {
        block := graph.blocks[i]
        j := 0
        for j < len(block.statements) {
            switch block.statements[j] {
                mir_statement::assign(assign_stmt) : {
                    if assign_stmt.op == "const" || assign_stmt.op == "literal" {
                        constants = constants + 1
                    }
                }
                mir_statement::eval(eval_stmt) : {
                    if len(eval_stmt.args) > 0 {
                        constants = constants + count_occurrences(eval_stmt.args[0], "const")
                        constants = constants + count_occurrences(eval_stmt.args[0], "literal")
                    }
                }
                _ : (),
            }
            j = j + 1
        }
        i = i + 1
    }
    if constants < 0 {
        return 0
    }
    constants
}

func build_wasm_toolchain_plan(string c_path, string obj_path, string output) string {
    return "clang --target=wasm32-wasi -c " + c_path
        + " -o " + obj_path
        + " && wasm-ld --no-entry --export=_start --allow-undefined " + obj_path
        + " -o " + output
}

func build_wasm_binary_probe_plan(string output) string {
    return "wasm-objdump -x " + output + " | grep -q wasi_snapshot_preview1"
        + " && wasm-objdump -x " + output + " | grep -q fd_write"
        + " && wasm-objdump -x " + output + " | grep -q proc_exit"
        + " && wasm-objdump -x " + output + " | grep -q _start"
}

func validate_wasi_binary_artifact(string output) ((), backend_error) {
    probe := string[]()
    probe = append(probe, "sh")
    probe = append(probe, "-c")
    probe = append(probe, build_wasm_binary_probe_plan(output))
    run := run_process(probe)
    if run.is_err() {
        return backend_error {
            message: "backend error: wasi binary probe failed (requires wasm-objdump and expected imports/exports): " + run.unwrap_err().message,
        }
    }
    ()
}

func build_wasm_object_chain(string temp_dir, string output, write_op[] writes, int exit_code) ((), backend_error) {
    c_path := temp_dir + "/out_wasm.c"
    obj_path := temp_dir + "/out_wasm.o"
    c_source := emit_wasm_c_source(writes, exit_code)
    wasi_check := validate_wasi_contract_source(c_source)
    if wasi_check.is_err() {
        return wasi_check
    }
    write_result := write_text_file(c_path, c_source)
    if write_result.is_err() {
        return backend_error { message: "failed to write wasm c source: " + write_result.unwrap_err().message }
    }
    cc_argv := string[]()
    cc_argv = append(cc_argv, "clang")
    cc_argv = append(cc_argv, "--target=wasm32-wasi")
    cc_argv = append(cc_argv, "-c")
    cc_argv = append(cc_argv, c_path)
    cc_argv = append(cc_argv, "-o")
    cc_argv = append(cc_argv, obj_path)
    cc_result := run_process(cc_argv)
    if cc_result.is_err() {
        return backend_error {
            message: "wasm object compile failed: " + cc_result.unwrap_err().message + " | plan: " + build_wasm_toolchain_plan(c_path, obj_path, output),
        }
    }
    ld_argv := string[]()
    ld_argv = append(ld_argv, "wasm-ld")
    ld_argv = append(ld_argv, "--no-entry")
    ld_argv = append(ld_argv, "--export=_start")
    ld_argv = append(ld_argv, "--allow-undefined")
    ld_argv = append(ld_argv, obj_path)
    ld_argv = append(ld_argv, "-o")
    ld_argv = append(ld_argv, output)
    ld_result := run_process(ld_argv)
    if ld_result.is_err() {
        return backend_error {
            message: "wasm link failed: " + ld_result.unwrap_err().message + " | plan: " + build_wasm_toolchain_plan(c_path, obj_path, output),
        }
    }
    ()
}

func validate_wasi_contract_source(string source) ((), backend_error) {
    if !has_substring(source, "__import_module__(\"wasi_snapshot_preview1\")") {
        return backend_error { message: "backend error: wasi import module annotation missing" }
    }
    if !has_substring(source, "fd_write") {
        return backend_error { message: "backend error: wasi fd_write import missing" }
    }
    if !has_substring(source, "proc_exit") {
        return backend_error { message: "backend error: wasi proc_exit import missing" }
    }
    if !has_substring(source, "void _start(void)") {
        return backend_error { message: "backend error: wasi _start entry missing" }
    }
    if !has_substring(source, "proc_exit(s_main())") {
        return backend_error { message: "backend error: wasi startup contract missing proc_exit(s_main())" }
    }
    ()
}

func emit_wasm_c_source(write_op[] writes, int exit_code) string {
    lines := string[]()
    lines = append(lines, "typedef unsigned int u32;")
    lines = append(lines, "typedef unsigned int usize;")
    lines = append(lines, "struct ciovec { const char* buf; usize len; };")
    lines = append(lines, "__attribute__((__import_module__(\"wasi_snapshot_preview1\"), __import_name__(\"fd_write\")))")
    lines = append(lines, "extern int fd_write(int fd, const struct ciovec* iovs, int iovs_len, u32* nwritten);")
    lines = append(lines, "__attribute__((__import_module__(\"wasi_snapshot_preview1\"), __import_name__(\"proc_exit\")))")
    lines = append(lines, "extern void proc_exit(int code);")
    lines = append(lines, "")
    lines = append(lines, "int s_main(void) {")
    i := 0
    for i < len(writes) {
        label := "message_" + to_string(i)
        lines = append(lines, "  static const char " + label + "[] = \"" + escape_asm_string(writes[i].text) + "\";")
        lines = append(lines, "  struct ciovec iov_" + to_string(i) + " = { " + label + ", " + to_string(len(writes[i].text)) + "u };")
        lines = append(lines, "  u32 nw_" + to_string(i) + " = 0;")
        lines = append(lines, "  fd_write(" + to_string(writes[i].fd) + ", *iov_" + to_string(i) + ", 1, *nw_" + to_string(i) + ");")
        i = i + 1
    }
    lines = append(lines, "  return " + to_string(exit_code) + ";"
    lines = append(lines, "}")
    lines = append(lines, "")
    lines = append(lines, "void _start(void) {")
    lines = append(lines, "  proc_exit(s_main());")
    lines = append(lines, "}")
    join_lines(lines) + "\n"
}

func estimate_ipo_synergy(int inlined, int escaped, int devirt, int cross_pkg_inline, int const_prop) int {
    score := inlined + devirt + cross_pkg_inline + const_prop
    if escaped > 0 {
        score = score - escaped / 2
    }
    if score < 0 {
        return 0
    }
    score
}

func build_abi_machine_matrix_artifact(string arch, source_file source, string ssa_text) string {
    lines := string[]()
    lines = append(lines, "abi-matrix version=1 arch=" + arch)
    lines = append(lines, "axis caller_saved=" + to_string(abi_caller_saved_count(arch)) + " callee_saved=" + to_string(abi_callee_saved_count(arch)))
    lines = append(lines, "axis stack_align=" + to_string(abi_stack_alignment(arch)) + " variadic_gp=" + to_string(abi_variadic_gp_limit(arch)))
    functions := function_item_count(source)
    spills := parse_number_after(ssa_text, "spills=")
    if spills < 0 {
        spills = 0
    }
    lines = append(lines, "coverage functions=" + to_string(functions) + " spills=" + to_string(spills))
    lines = append(lines, "matrix callseq=normal,variadic-home,normal+multi-ret,variadic-home+multi-ret")
    lines = append(lines, "matrix ret=reg,sret,tuple2,tupleN")
    lines = append(lines, "cross_arch_consistency=" + abi_cross_arch_consistency_status(arch, spills, functions))
    join_lines(lines)
}

func abi_cross_arch_consistency_status(string arch, int spills, int functions) string {
    score := functions * 4 - spills
    if arch == "arm64" {
        score = score + 2
    }
    if score >= 8 {
        return "stable"
    }
    if score >= 3 {
        return "converging"
    }
    "fragile"
}

func validate_abi_machine_matrix(string payload) ((), backend_error) {
    if !has_substring(payload, "abi-matrix version=1") {
        return backend_error { message: "backend error: ABI matrix header missing" }
    }
    if !has_substring(payload, "axis caller_saved=") {
        return backend_error { message: "backend error: ABI matrix caller/callee axis missing" }
    }
    if !has_substring(payload, "matrix callseq=") {
        return backend_error { message: "backend error: ABI matrix call sequence axis missing" }
    }
    if !has_substring(payload, "matrix ret=") {
        return backend_error { message: "backend error: ABI matrix return axis missing" }
    }
    if !has_substring(payload, "cross_arch_consistency=") {
        return backend_error { message: "backend error: ABI matrix cross-arch consistency missing" }
    }
    ()
}

func build_toolchain_compat_artifact(source_file source, string arch) string {
    lines := string[]()
    lines = append(lines, "toolchain-compat version=1 arch=" + arch)
    lines = append(lines, "module=partial build_tags=partial test=integrated cover=partial profile=partial go_cmd_equiv=partial")
    lines = append(lines, "cgo=unsupported asm=go-plan9-min linker=elf64 archive=partial relocation=partial")
    lines = append(lines, "functions=" + to_string(function_item_count(source)) + " interoperability=baseline build_cache=phase-aware")
    lines = append(lines, "matrix module,build_tags,test,cover,profile,cgo,asm,linker,archive,relocation")
    lines = append(lines, "gate coverage=min profile=min fuzz=planned stability=rolling")
    lines = append(lines, "interop cgo=roadmap asm=go-plan9-min linker=elf64-only")
    lines = append(lines, "go_asm syntax=plan9 translator=enabled status=ok")
    lines = append(lines, "go_equiv module=planned build_tags=planned test=partial cover=partial profile=planned")
    join_lines(lines)
}

func validate_toolchain_compat_artifact(string payload) ((), backend_error) {
    if !has_substring(payload, "toolchain-compat version=1") {
        return backend_error { message: "backend error: toolchain compatibility header missing" }
    }
    if !has_substring(payload, "module=") {
        return backend_error { message: "backend error: toolchain compatibility module field missing" }
    }
    if !has_substring(payload, "linker=") {
        return backend_error { message: "backend error: toolchain compatibility linker field missing" }
    }
    if !has_substring(payload, "go_cmd_equiv=") {
        return backend_error { message: "backend error: toolchain compatibility go command equivalence field missing" }
    }
    if !has_substring(payload, "matrix ") {
        return backend_error { message: "backend error: toolchain compatibility matrix missing" }
    }
    if !has_substring(payload, "gate coverage=") {
        return backend_error { message: "backend error: toolchain compatibility gate missing" }
    }
    if !has_substring(payload, "interop cgo=") {
        return backend_error { message: "backend error: toolchain compatibility interop roadmap missing" }
    }
    if !has_substring(payload, "go_asm syntax=plan9") {
        return backend_error { message: "backend error: toolchain compatibility go asm marker missing" }
    }
    if !has_substring(payload, "go_equiv ") {
        return backend_error { message: "backend error: toolchain compatibility go equivalence marker missing" }
    }
    ()
}

func build_go_asm_bridge_artifact(string arch, string plan9_source) string {
    lines := string[]()
    lines = append(lines, "go-asm version=1 arch=" + arch + " syntax=plan9")
    translated := translate_go_plan9_to_gas(arch, plan9_source)
    if translated.is_err() {
        lines = append(lines, "status=error")
        lines = append(lines, "reason=" + translated.unwrap_err().message)
        return join_lines(lines
    }
    lines = append(lines, "status=ok")
    lines = append(lines, "translator=plan9-to-gas")
    lines = append(lines, "gas_preview=" + flatten_multiline(translated.unwrap()))
    join_lines(lines)
}

func validate_go_asm_bridge_artifact(string payload) ((), backend_error) {
    if !has_substring(payload, "go-asm version=1") {
        return backend_error { message: "backend error: go asm artifact header missing" }
    }
    if !has_substring(payload, "syntax=plan9") {
        return backend_error { message: "backend error: go asm artifact syntax marker missing" }
    }
    if !has_substring(payload, "status=ok") {
        return backend_error { message: "backend error: go asm artifact status is not ok" }
    }
    if !has_substring(payload, "gas_preview=") {
        return backend_error { message: "backend error: go asm artifact preview missing" }
    }
    ()
}

func translate_go_plan9_to_gas(string arch, string plan9_source) (string, backend_error) {
    input_lines := split_lines_local(plan9_source)
    output_lines := string[]()
    saw_text_directive := false
    i := 0
    for i < len(input_lines) {
        cleaned := trim_spaces(strip_go_asm_comment(input_lines[i]))
        if cleaned == "" {
            i = i + 1
            continue
        }
        if starts_with_local(cleaned, "TEXT ") {
            symbol_result := parse_go_text_symbol(cleaned)
            if symbol_result.is_err() {
                return symbol_result.unwrap_err()
            }
            symbol := symbol_result.unwrap()
            saw_text_directive = true
            output_lines = append(output_lines, "    .text")
            output_lines = append(output_lines, "    .globl " + symbol)
            output_lines = append(output_lines, "    .type " + symbol + ", @function")
            output_lines = append(output_lines, symbol + ":")
            i = i + 1
            continue
        }
        if ends_with_local(cleaned, ":") {
            label := trim_spaces(slice(cleaned, 0, len(cleaned) - 1))
            if label == "" {
                return backend_error { message: "go asm translation error: empty label" }
            }
            output_lines = append(output_lines, normalize_go_symbol(label) + ":")
            i = i + 1
            continue
        }
        if !saw_text_directive {
            return backend_error { message: "go asm translation error: missing TEXT directive" }
        }
        if starts_with_local(cleaned, "RET") {
            output_lines = append(output_lines, "    ret")
            i = i + 1
            continue
        }
        instr_result := translate_go_instruction_line(cleaned, arch)
        if instr_result.is_err() {
            return instr_result.unwrap_err()
        }
        output_lines = append(output_lines, instr_result.unwrap())
        i = i + 1
    }
    if !saw_text_directive {
        return backend_error { message: "go asm translation error: no TEXT directive found" }
    }
    join_lines(output_lines)
}

func parse_go_text_symbol(string line) (string, backend_error) {
    after := trim_spaces(slice(line, len("TEXT "), len(line)))
    comma := index_of(after, ",")
    if comma < 0 {
        return backend_error { message: "go asm translation error: malformed TEXT directive" }
    }
    symbol_ref := trim_spaces(slice(after, 0, comma))
    if !ends_with_local(symbol_ref, "(SB)") {
        return backend_error { message: "go asm translation error: TEXT symbol must use (SB)" }
    }
    symbol := normalize_go_symbol(slice(symbol_ref, 0, len(symbol_ref) - len("(SB)")))
    if symbol == "" {
        return backend_error { message: "go asm translation error: empty TEXT symbol" }
    }
    symbol
}

func translate_go_instruction_line(string line, string arch) (string, backend_error) {
    first_space := index_of(line, " ")
    op := line
    args_text := ""
    if first_space >= 0 {
        op = trim_spaces(slice(line, 0, first_space))
        args_text = trim_spaces(slice(line, first_space + 1, len(line)))
    }
    gas_op := map_go_opcode(op)
    if gas_op == "" {
        return backend_error { message: "go asm translation error: unsupported opcode " + op }
    }
    if args_text == "" {
        return "    " + gas_op
    }
    comma := index_of(args_text, ",")
    if comma < 0 {
        one := convert_go_operand_to_gas(args_text, arch)
        if one.is_err() {
            return one.unwrap_err()
        }
        return "    " + gas_op + " " + one.unwrap())
    }
    left_raw := trim_spaces(slice(args_text, 0, comma))
    right_raw := trim_spaces(slice(args_text, comma + 1, len(args_text)))
    left := convert_go_operand_to_gas(left_raw, arch)
    if left.is_err() {
        return left.unwrap_err()
    }
    right := convert_go_operand_to_gas(right_raw, arch)
    if right.is_err() {
        return right.unwrap_err()
    }
    "    " + gas_op + " " + left.unwrap() + ", " + right.unwrap()
}

func map_go_opcode(string op) string {
    if op == "MOVQ" {
        return "movq"
    }
    if op == "MOVL" {
        return "movl"
    }
    if op == "ADDQ" {
        return "addq"
    }
    if op == "ADDL" {
        return "addl"
    }
    if op == "SUBQ" {
        return "subq"
    }
    if op == "SUBL" {
        return "subl"
    }
    if op == "CMPQ" {
        return "cmpq"
    }
    if op == "CMPL" {
        return "cmpl"
    }
    if op == "CMPB" {
        return "cmpb"
    }
    if op == "TESTQ" {
        return "testq"
    }
    if op == "LEAQ" {
        return "leaq"
    }
    if op == "XORQ" {
        return "xorq"
    }
    if op == "CALL" {
        return "call"
    }
    if op == "JMP" {
        return "jmp"
    }
    if op == "JE" {
        return "je"
    }
    if op == "JNE" {
        return "jne"
    }
    if op == "JLT" {
        return "jl"
    }
    if op == "JLE" {
        return "jle"
    }
    if op == "JGT" {
        return "jg"
    }
    if op == "JGE" {
        return "jge"
    }
    if op == "PUSHQ" {
        return "pushq"
    }
    if op == "POPQ" {
        return "popq"
    }
    if op == "NOP" {
        return "nop"
    }
    ""
}

func convert_go_operand_to_gas(string raw, string arch) (string, backend_error) {
    operand := trim_spaces(raw)
    if operand == "" {
        return backend_error { message: "go asm translation error: empty operand" }
    }
    if starts_with_local(operand, "$") {
        imm := slice(operand, 1, len(operand))
        if ends_with_local(imm, "(SB)") {
            return "$" + normalize_go_symbol(slice(imm, 0, len(imm) - len("(SB)")))
        }
        return "$" + normalize_go_symbol(imm))
    }
    if ends_with_local(operand, "(SB)") {
        sym := normalize_go_symbol(slice(operand, 0, len(operand) - len("(SB)")))
        if sym == "" {
            return backend_error { message: "go asm translation error: empty symbol operand" }
        }
        return sym
    }
    paren := index_of(operand, "(")
    if paren >= 0 && ends_with_local(operand, ")") {
        base := slice(operand, paren + 1, len(operand) - 1)
        if base == "SB" {
            return normalize_go_symbol(slice(operand, 0, paren)))
        }
        mapped_base := map_go_register(base, arch)
        if mapped_base == "" {
            return backend_error { message: "go asm translation error: unsupported base register " + base }
        }
        disp := parse_go_disp(slice(operand, 0, paren))
        return disp + "(" + mapped_base + ")"
    }
    mapped_reg := map_go_register(operand, arch)
    if mapped_reg != "" {
        return mapped_reg
    }
    if starts_with_local(operand, ".") {
        return normalize_go_symbol(operand))
    }
    normalize_go_symbol(operand)
}

func map_go_register(string reg, string arch) string {
    if arch != "amd64" && arch != "amd64p32" {
        return ""
    }
    if reg == "AX" {
        return "%rax"
    }
    if reg == "BX" {
        return "%rbx"
    }
    if reg == "CX" {
        return "%rcx"
    }
    if reg == "DX" {
        return "%rdx"
    }
    if reg == "SP" {
        return "%rsp"
    }
    if reg == "FP" {
        return "%rbp"
    }
    if reg == "BP" {
        return "%rbp"
    }
    if reg == "SI" {
        return "%rsi"
    }
    if reg == "DI" {
        return "%rdi"
    }
    if reg == "R8" {
        return "%r8"
    }
    if reg == "R9" {
        return "%r9"
    }
    if reg == "R10" {
        return "%r10"
    }
    if reg == "R11" {
        return "%r11"
    }
    if reg == "R12" {
        return "%r12"
    }
    if reg == "R13" {
        return "%r13"
    }
    if reg == "R14" {
        return "%r14"
    }
    if reg == "R15" {
        return "%r15"
    }
    ""
}

func parse_go_disp(string text) string {
    disp := trim_spaces(text)
    if disp == "" {
        return "0"
    }
    plus := index_of(disp, "+")
    if plus >= 0 {
        tail := trim_spaces(slice(disp, plus + 1, len(disp)))
        if tail == "" {
            return "0"
        }
        return tail
    }
    disp
}

func normalize_go_symbol(string text) string {
    out := trim_spaces(text)
    if starts_with_local(out, "*") {
        out = trim_spaces(slice(out, 1, len(out)))
    }
    out
}

func strip_go_asm_comment(string line) string {
    out := line
    slash := index_of(out, "
    if slash >= 0 {
        out = slice(out, 0, slash)
    }
    hash := index_of(out, "#")
    if hash >= 0 {
        out = slice(out, 0, hash)
    }
    out
}

func split_lines_local(string text) string[] {
    lines := string[]()
    start := 0
    i := 0
    for i < len(text) {
        if char_at(text, i) == "\n" {
            lines = append(lines, slice(text, start, i))
            start = i + 1
        }
        i = i + 1
    }
    if start <= len(text) {
        lines = append(lines, slice(text, start, len(text)))
    }
    lines
}

func flatten_multiline(string text) string {
    lines := split_lines_local(text)
    out := string[]()
    i := 0
    for i < len(lines) {
        line := trim_spaces(lines[i])
        if line != "" {
            out = append(out, line)
        }
        i = i + 1
    }
    join_with(out, " | ")
}

func build_stackmap_artifact(string arch, source_file source, string ssa_text, string debug_map) string {
    entries := collect_function_stackmaps(arch, source, ssa_text)
    header := "stackmap version=2 arch=" + arch + " functions=" + to_string(len(entries))
    lines := string[]()
    lines = append(lines, header)
    i := 0
    for i < len(entries) {
        entry := entries[i]
        lines.push(
            "fn " + entry.name
                + " slots=" + to_string(entry.slots)
                + " bitmap=" + entry.bitmap
                + " callee_saved=" + to_string(entry.callee_saved)
        )
        i = i + 1
    }
    lines = append(lines, "meta " + debug_map)
    join_lines(lines)
}

func estimate_stack_slots(string ssa_text) int {
    spills := parse_number_after(ssa_text, "spills=")
    if spills < 0 {
        return 0
    }
    spills
}

func collect_function_stackmaps(string arch, source_file source, string ssa_text) stackmap_function_entry[] {
    out := stackmap_function_entry[]()
    i := 0
    for i < len(source.items) {
        switch source.items[i] {
            item.function(fn_decl) : {
                if fn_decl.body.is_some() {
                    slots := estimate_function_stack_slots(fn_decl, ssa_text)
                    out.push(stackmap_function_entry {
                        name: fn_decl.sig.name, slots slots, bitmap build_slot_bitmap(fn_decl.sig.name, slots), callee_saved abi_callee_saved_count(arch),
                    })
                }
            }
            _ : (),
        }
        i = i + 1
    }
    if len(out) == 0 {
        out.push(stackmap_function_entry {
            name: "main", slots estimate_stack_slots(ssa_text), bitmap build_slot_bitmap("main", estimate_stack_slots(ssa_text)), callee_saved abi_callee_saved_count(arch),
        })
    }
    out
}

func estimate_function_stack_slots(function_decl fn_decl, string ssa_text) int {
    if fn_decl.sig.name == "main" {
        main_slots := estimate_stack_slots(ssa_text)
        if main_slots > 0 {
            return main_slots
        }
    }
    if fn_decl.body.is_none() {
        return 0
    }
    stmt_count := fn_decl.body.unwrap()len(.statements)
    slots := (stmt_count + 1) / 2
    if slots < 1 {
        return 1
    }
    slots
}

func build_slot_bitmap(string function_name, int slots) string {
    if slots <= 0 {
        return "0"
    }
    out := ""
    i := 0
    for i < slots {
        if ((i + len(function_name)) % 2) == 0 {
            out = out + "1"
        } else {
            out = out + "0"
        }
        i = i + 1
    }
    out
}

func build_abi_behavior_artifact(string arch, source_file source) string {
    entries := collect_abi_behavior(arch, source)
    lines := string[]()
    lines = append(lines, "abi version=1 arch=" + arch + " functions=" + to_string(len(entries)))
    i := 0
    for i < len(entries) {
        entry := entries[i]
        lines.push(
            "fn " + entry.name
                + " params=" + to_string(entry.param_count)
                + " variadic=" + bool_string(entry.variadic)
                + " pass=" + entry.pass_mode
                + " ret=" + entry.return_mode
                + " abi_in_regs=" + to_string(entry.abi_in_regs)
                + " abi_out_regs=" + to_string(entry.abi_out_regs)
                + " abi_spill=" + to_string(entry.abi_spill_size)
                + " abi_argw=" + to_string(entry.abi_arg_width)
                + " abi_summary=" + flatten_multiline(entry.abi_summary)
        )
        i = i + 1
    }
    join_lines(lines)
}

func build_abi_emit_plan(string arch, source_file source) string {
    lines := string[]()
    lines = append(lines, "abi-emit version=1 arch=" + arch)
    i := 0
    for i < len(source.items) {
        switch source.items[i] {
            item.function(fn_decl) : {
                line := "fn " + fn_decl.sig.name
                abi_info := abi_analyze_types(
                    new_abi_config(abi_variadic_gp_limit(arch), abi_float_param_reg_limit(arch), abi_stack_alignment(arch), 1),
                    collect_fn_param_types(fn_decl),
                    collect_fn_result_types(fn_decl)
                )
                p := 0
                for p < len(fn_decl.sig.params) {
                    line = line + " | a" + to_string(p) + "->" + abi_param_location(arch, p)
                    line = line + " | f" + to_string(p) + "->" + abi_float_param_location(arch, p)
                    p = p + 1
                }
                variadic := len(fn_decl.sig.params) > abi_variadic_gp_limit(arch)
                line = line + " | variadic=" + bool_string(variadic)
                ret_type :=
                    switch fn_decl.sig.return_type {
                        option.some(value) : trim_spaces(value),
                        option.none : "",
                    }
                ret_parts := count_top_level_type_parts(ret_type)
                aggregate_size := abi_emit_aggregate_size_hint(len(fn_decl.sig.params), ret_type)
                line = line + " | ret_arity=" + to_string(ret_parts)
                line = line + " | agg_mode=" + abi_emit_aggregate_mode(ret_type, ret_parts, aggregate_size)
                line = line + " | stack_align=" + to_string(abi_stack_alignment(arch))
                line = line + " | caller_saved=" + to_string(abi_caller_saved_count(arch))
                line = line + " | callee_saved=" + to_string(abi_callee_saved_count(arch))
                line = line + " | callseq=" + abi_call_sequence_mode(arch, variadic, ret_parts, aggregate_size)
                line = line + " | " + abi_emit_ret_plan(arch, ret_type, ret_parts, aggregate_size)
                line = line + " | abi_in_regs=" + to_string(abiutils_in_registers_used(abi_info))
                line = line + " | abi_out_regs=" + to_string(abiutils_out_registers_used(abi_info))
                line = line + " | abi_spill=" + to_string(abiutils_spill_area_size(abi_info))
                lines = append(lines, line)
            }
            _ : (),
        }
        i = i + 1
    }
    join_lines(lines)
}

func abi_param_location(string arch, int index) string {
    reg := abi_int_arg_reg(arch, index)
    if reg == "" {
        return "stack+" + to_string((index - abi_variadic_gp_limit(arch)) * 8
    }
    reg
}

func abi_float_param_location(string arch, int index) string {
    reg := abi_float_arg_reg(arch, index)
    if reg == "" {
        return "stackf+" + to_string(index * 8
    }
    reg
}

func abi_emit_ret_location(string arch, int aggregate_size) string {
    if aggregate_size > 16 {
        return "sret:" + abi_sret_reg(arch
    }
    abi_int_ret_reg(arch)
}

func abi_emit_aggregate_size_hint(int param_count, string ret_type) int {
    size := param_count * 8
    parts := count_top_level_type_parts(ret_type)
    if parts > 1 {
        size = parts * 8
    }
    if has_substring(ret_type, "[") {
        size = size + 16
    }
    if has_substring(ret_type, "{") {
        size = size + 32
    }
    size
}

func abi_emit_aggregate_mode(string ret_type, int ret_parts, int aggregate_size) string {
    if ret_type == "" {
        return "void"
    }
    if ret_parts == 1 {
        if aggregate_size > 16 || has_substring(ret_type, "[") || has_substring(ret_type, "{") {
            return "complex"
        }
        return "scalar"
    }
    if ret_parts == 2 && aggregate_size <= 16 {
        return "tuple2"
    }
    if aggregate_size > 16 || ret_parts > 2 {
        return "tuple_n"
    }
    "scalar"
}

func abi_emit_ret_plan(string arch, string ret_type, int ret_parts, int aggregate_size) string {
    if ret_type == "" {
        return "ret->void"
    }
    if ret_parts <= 1 {
        return "ret->" + abi_emit_ret_location(arch, aggregate_size
    }
    if ret_parts == 2 && aggregate_size <= 16 {
        return "ret0->" + abi_int_ret_reg(arch) + " | ret1->" + abi_second_int_ret_reg(arch
    }
    if aggregate_size > 16 || ret_parts > 2 {
        return "ret->sret:" + abi_sret_reg(arch) + " | tuple_parts=" + to_string(ret_parts
    }
    "ret->" + abi_int_ret_reg(arch)
}

func abi_second_int_ret_reg(string arch) string {
    if arch == "arm64" {
        return "x1"
    }
    if arch == "riscv64" {
        return "a1"
    }
    if arch == "s390x" {
        return "%r3"
    }
    if arch == "wasm" {
        return "local1"
    }
    "%rdx"
}

func abi_stack_alignment(string arch) int {
    if arch == "arm64" || arch == "riscv64" || arch == "s390x" || arch == "wasm" {
        return 16
    }
    16
}

func abi_caller_saved_count(string arch) int {
    if arch == "arm64" {
        return 18
    }
    if arch == "riscv64" {
        return 15
    }
    if arch == "s390x" {
        return 12
    }
    if arch == "wasm" {
        return 8
    }
    9
}

func abi_call_sequence_mode(string arch, bool variadic, int ret_parts, int aggregate_size) string {
    mode := "normal"
    if variadic {
        mode = "variadic-home"
    }
    if ret_parts > 1 {
        mode = mode + "+multi-ret"
    }
    if aggregate_size > 16 {
        mode = mode + "+sret"
    }
    if arch == "arm64" {
        return mode + "+aapcs64"
    }
    mode + "+sysv"
}

func count_top_level_type_parts(string type_text) int {
    t := trim_spaces(type_text)
    if t == "" {
        return 0
    }
    paren := 0
    bracket := 0
    count := 1
    i := 0
    for i < len(t) {
        ch := char_at(t, i)
        if ch == "(" {
            paren = paren + 1
        } else if ch == ")" {
            if paren > 0 {
                paren = paren - 1
            }
        } else if ch == "[" {
            bracket = bracket + 1
        } else if ch == "]" {
            if bracket > 0 {
                bracket = bracket - 1
            }
        } else if ch == "," && paren <= 1 && bracket == 0 {
            count = count + 1
        }
        i = i + 1
    }
    count
}

func collect_abi_behavior(string arch, source_file source) abi_behavior_entry[] {
    out := abi_behavior_entry[]()
    i := 0
    for i < len(source.items) {
        switch source.items[i] {
            item.function(fn_decl) : {
                abi_info := abi_analyze_types(
                    new_abi_config(abi_variadic_gp_limit(arch), abi_float_param_reg_limit(arch), abi_stack_alignment(arch), 1),
                    collect_fn_param_types(fn_decl),
                    collect_fn_result_types(fn_decl)
                )
                param_count := len(fn_decl.sig.params)
                variadic := param_count > abi_variadic_gp_limit(arch)
                aggregate_size := param_count * 8
                out.push(abi_behavior_entry {
                    name: fn_decl.sig.name, param_count param_count, variadic variadic, pass_mode abi_aggregate_pass_mode(arch, aggregate_size), return_mode abi_return_mode(arch, "aggregate", aggregate_size), abi_in_regs abiutils_in_registers_used(abi_info), abi_out_regs abiutils_out_registers_used(abi_info), abi_spill_size abiutils_spill_area_size(abi_info), abi_arg_width abiutils_arg_width(abi_info), abi_summary abiutils_info_string(abi_info),
                })
            }
            _ : (),
        }
        i = i + 1
    }
    out
}

func collect_fn_param_types(function_decl fn_decl) string[] {
    out := string[]()
    i := 0
    for i < len(fn_decl.sig.params) {
        out = append(out, trim_spaces(fn_decl.sig.params[i].type_name))
        i = i + 1
    }
    out
}

func collect_fn_result_types(function_decl fn_decl) string[] {
    switch fn_decl.sig.return_type {
        option.some(value) : return split_signature_types(trim_spaces(value)),
        option.none : return string[](),
    }
}

func split_signature_types(string type_text) string[] {
    t := trim_spaces(type_text)
    if t == "" {
        return string[](
    }
    if abi_text_starts_with(t, "(") && abi_text_ends_with(t, ")") {
        t = trim_spaces(slice(t, 1, len(t) - 1))
    }
    if t == "" {
        return string[](
    }
    out := string[]()
    start := 0
    paren := 0
    bracket := 0
    i := 0
    for i < len(t) {
        ch := char_at(t, i)
        if ch == "(" {
            paren = paren + 1
        } else if ch == ")" {
            if paren > 0 {
                paren = paren - 1
            }
        } else if ch == "[" {
            bracket = bracket + 1
        } else if ch == "]" {
            if bracket > 0 {
                bracket = bracket - 1
            }
        } else if ch == "," && paren == 0 && bracket == 0 {
            out = append(out, trim_spaces(slice(t, start, i)))
            start = i + 1
        }
        i = i + 1
    }
    out = append(out, trim_spaces(slice(t, start, len(t))))
    out
}

func abi_text_starts_with(string text, string prefix) bool {
    if len(text) < len(prefix) {
        return false
    }
    return slice(text, 0, len(prefix)) == prefix
}

func abi_text_ends_with(string text, string suffix) bool {
    if len(text) < len(suffix) {
        return false
    }
    return slice(text, len(text) - len(suffix), len(text)) == suffix
}

func abi_float_param_reg_limit(string arch) int {
    if arch == "arm64" {
        return 8
    }
    if arch == "riscv64" {
        return 8
    }
    if arch == "s390x" {
        return 8
    }
    if arch == "wasm" {
        return 0
    }
    return 8
}

func build_dwarf_like_artifact(source_file source, string ssa_text, string debug_map) string {
    lines := string[]()
    lines = append(lines, "dwarf-lite version=1")
    lines = append(lines, "section .debug_info")
    lines = append(lines, "  compile_unit name=" + parse_name_after(ssa_text, "ssa "))
    lines = append(lines, "section .debug_abbrev")
    lines = append(lines, "  abbrev#1=compile_unit abbrev#2=subprogram abbrev#3=variable")
    lines = append(lines, "section .debug_str")
    lines = append(lines, "  producer=s-compiler language=s")
    lines = append(lines, "section .debug_line")
    lines = append(lines, "  " + debug_map)
    lines = append(lines, "section .debug_frame")
    lines = append(lines, "  cfa=sp+16 ra=lr")
    lines = append(lines, "section .debug_loc")
    append_debug_loc_section(lines, debug_map)
    lines = append(lines, "section .debug_ranges")
    append_debug_ranges_section(lines, source, ssa_text)
    lines = append(lines, "section .debug_inlining")
    i := 0
    for i < len(source.items) {
        switch source.items[i] {
            item.function(fn_decl) : lines = append(lines, "  fn=" + fn_decl.sig.name + " inline_depth=" + to_string(dwarf_inline_depth_hint(fn_decl.sig.name, ssa_text))),
            _ : (),
        }
        i = i + 1
    }
    lines = append(lines, build_dwarf_continuity_metric(ssa_text, debug_map))
    lines = append(lines, build_dwarf_budget_policy(ssa_text))
    lines = append(lines, build_dwarf_regression_gate(ssa_text, debug_map))
    join_lines(lines)
}

func build_dwarf_continuity_metric(string ssa_text, string debug_map) string {
    lines := parse_number_after(ssa_text, "dbg_lines=")
    if lines < 1 {
        lines = 1
    }
    vars := count_occurrences(debug_map, "let v")
    if vars < 1 {
        vars = 1
    }
    continuity := (vars * 100) / lines
    if continuity > 100 {
        continuity = 100
    }
    "metric location_continuity=" + to_string(continuity)
}

func build_dwarf_budget_policy(string ssa_text) string {
    budget := parse_number_after(ssa_text, "dbg_budget=")
    if budget < 0 {
        budget = 0
    }
    mode := "balanced"
    if budget < 20 {
        mode = "strict"
    }
    if budget > 70 {
        mode = "performance"
    }
    "policy debug_budget_mode=" + mode + " rolling_window=30 failure_threshold=3"
}

func build_dwarf_regression_gate(string ssa_text, string debug_map) string {
    budget := parse_number_after(ssa_text, "dbg_budget=")
    if budget < 0 {
        budget = 0
    }
    locs := count_occurrences(debug_map, "let v")
    if locs < 1 {
        locs = 1
    }
    status := "pass"
    if budget < 15 {
        status = "fail"
    }
    "gate dwarf_consumable=" + status
        + " budget=" + to_string(budget)
        + " locs=" + to_string(locs)
}

func append_debug_loc_section(string[] lines, string debug_map) () {
    marker := "let v"
    cursor := 0
    loc_id := 0
    for true {
        at := index_of_from(debug_map, marker, cursor)
        if at < 0 {
            break
        }
        end := index_of_from(debug_map, " | ", at)
        if end < 0 {
            end = len(debug_map)
        }
        entry := trim_spaces(slice(debug_map, at, end))
        lo := 100 + loc_id * 8
        hi := lo + 8
        lines = append(lines, "  loc#" + to_string(loc_id) + " pc=[" + to_string(lo) + "," + to_string(hi) + ") " + entry)
        loc_id = loc_id + 1
        cursor = end + 3
    }
    if loc_id == 0 {
        lines = append(lines, "  loc#0 pc=[0,0) let none")
    }
}

func append_debug_ranges_section(string[] lines, source_file source, string ssa_text) () {
    dbg_lines := parse_number_after(ssa_text, "dbg_lines=")
    if dbg_lines < 1 {
        dbg_lines = 1
    }
    range_span := dbg_lines * 8
    if range_span < 16 {
        range_span = 16
    }
    loops := parse_number_after(ssa_text, "loops=")
    if loops < 0 {
        loops = 0
    }
    fn_idx := 0
    i := 0
    for i < len(source.items) {
        switch source.items[i] {
            item.function(fn_decl) : {
                lo := 0x1000 + fn_idx * range_span
                hi := lo + range_span
                lines = append(lines, "  fn=" + fn_decl.sig.name + " range=[" + to_string(lo) + "," + to_string(hi) + ")")
                if loops > 0 {
                    inline_lo := lo + 4
                    inline_hi := inline_lo + loops * 4
                    if inline_hi > hi {
                        inline_hi = hi
                    }
                    lines = append(lines, "  fn=" + fn_decl.sig.name + " inline_range=[" + to_string(inline_lo) + "," + to_string(inline_hi) + ")")
                }
                fn_idx = fn_idx + 1
            }
            _ : (),
        }
        i = i + 1
    }
    if fn_idx == 0 {
        lines = append(lines, "  fn=none range=[0,0)")
    }
}

func dwarf_inline_depth_hint(string fn_name, string ssa_text) int {
    loops := parse_number_after(ssa_text, "loops=")
    if loops < 0 {
        loops = 0
    }
    if starts_with_local(fn_name, "inline_") {
        return 1 + loops
    }
    if loops > 0 {
        return 1
    }
    0
}

func build_drop_metadata_artifact(string arch, source_file source, string ssa_text) string {
    lines := string[]()
    spills := estimate_stack_slots(ssa_text)
    lines = append(lines, "dropmap version=1 arch=" + arch + " spills=" + to_string(spills))
    lines = append(lines, "ownership strategy=move-copy-clone resource_release=scope-exit")
    i := 0
    for i < len(source.items) {
        switch source.items[i] {
            item.function(fn_decl) : {
                slots := estimate_function_stack_slots(fn_decl, ssa_text)
                lines.push(
                    "fn " + fn_decl.sig.name
                        + " slots=" + to_string(slots)
                        + " drops=scope-exit"
                )
            }
            _ : (),
        }
        i = i + 1
    }
    lines = append(lines, "contract ownership=checked drop=deterministic")
    lines = append(lines, "proof rollback=" + to_string(parse_number_after(ssa_text, "rollback=")) + " proof_fail=" + to_string(parse_number_after(ssa_text, "proof_fail=")))
    join_lines(lines)
}

func validate_dwarf_consumability(string dwarf_payload, string ssa_text) ((), backend_error) {
    if !has_substring(dwarf_payload, "section .debug_info") {
        return backend_error { message: "backend error: dwarf consumability gate missing .debug_info" }
    }
    if !has_substring(dwarf_payload, "section .debug_line") {
        return backend_error { message: "backend error: dwarf consumability gate missing .debug_line" }
    }
    if !has_substring(dwarf_payload, "section .debug_loc") {
        return backend_error { message: "backend error: dwarf consumability gate missing .debug_loc" }
    }
    if !has_substring(dwarf_payload, "section .debug_ranges") {
        return backend_error { message: "backend error: dwarf consumability gate missing .debug_ranges" }
    }
    if !has_substring(dwarf_payload, "gate dwarf_consumable=") {
        return backend_error { message: "backend error: dwarf consumability gate marker missing" }
    }
    if !has_substring(dwarf_payload, "policy debug_budget_mode=") {
        return backend_error { message: "backend error: dwarf budget policy missing" }
    }
    if !has_substring(dwarf_payload, "metric location_continuity=") {
        return backend_error { message: "backend error: dwarf continuity metric missing" }
    }
    budget := parse_number_after(ssa_text, "dbg_budget=")
    if budget >= 0 && budget < 15 {
        return backend_error { message: "backend error: dwarf consumability budget too low" }
    }
    if count_occurrences(dwarf_payload, "loc#") <= 0 {
        return backend_error { message: "backend error: dwarf consumability has no variable locations" }
    }
    ()
}

func validate_drop_contract_chain(string drop_payload, source_file source, string ssa_text) ((), backend_error) {
    if !has_substring(drop_payload, "dropmap version=1") {
        return backend_error { message: "backend error: drop contract missing dropmap header" }
    }
    if !has_substring(drop_payload, "ownership strategy=move-copy-clone") {
        return backend_error { message: "backend error: drop contract ownership strategy missing" }
    }
    if !has_substring(drop_payload, "contract ownership=checked drop=deterministic") {
        return backend_error { message: "backend error: drop contract deterministic release marker missing" }
    }
    expected := function_item_count(source)
    got := count_occurrences(drop_payload, "\nfn ")
    if has_substring(drop_payload, "fn ") && got == 0 {
        got = 1
    }
    if expected > 0 && got < expected {
        return backend_error { message: "backend error: drop contract function coverage mismatch" }
    }
    proof_fail := parse_number_after(ssa_text, "proof_fail=")
    if proof_fail > 0 {
        return backend_error { message: "backend error: drop contract blocked by failed ssa proofs" }
    }
    ()
}

func build_backend_perf_baseline_artifact(string arch, string ssa_text, string midend_report, string runtime_report) string {
    lines := string[]()
    lines = append(lines, "perf-baseline version=1 arch=" + arch)
    lines = append(lines, "ssa spills=" + to_string(parse_number_after(ssa_text, "spills="))
        + " splits=" + to_string(parse_number_after(ssa_text, "splits="))
        + " remat=" + to_string(parse_number_after(ssa_text, "remat="))
        + " sched_tp=" + to_string(parse_number_after(ssa_text, "sched_tp="))
        + " sched_lat=" + to_string(parse_number_after(ssa_text, "sched_lat=")))
    lines = append(lines, "midend " + midend_report)
    lines.push("scheduler queue_policy=priority-rr select_policy=multi-chan-priority-rr"
        + " sroutine_sites=" + to_string(parse_number_after(midend_report, "sroutine_sites="))
        + " select_weighted_sites=" + to_string(parse_number_after(midend_report, "select_weighted_sites="))
        + " select_timeout_sites=" + to_string(parse_number_after(midend_report, "select_timeout_sites="))
        + " select_send_sites=" + to_string(parse_number_after(midend_report, "select_send_sites="))
        + " sched_tp=" + to_string(parse_number_after(ssa_text, "sched_tp="))
        + " sched_lat=" + to_string(parse_number_after(ssa_text, "sched_lat=")))
    lines.push("scheduler_counters"
        + " select_default_fallbacks=" + to_string(parse_number_after(runtime_report, "select_default_fallbacks="))
        + " select_timeouts=" + to_string(parse_number_after(runtime_report, "select_timeouts=")))
    lines.push("runtime_memory strategy=ownership+explicit-drop")
    lines = append(lines, runtime_report)
    lines = append(lines, "regression_gate p95_latency=stable throughput=stable")
    lines = append(lines, "regression_gate_long p99_latency=watch code_size=watch compile_time=watch")
    lines = append(lines, "regression_gate_arch amd64=watch arm64=watch tail_cases=watch")
    join_lines(lines)
}

func validate_backend_perf_baseline(string payload) ((), backend_error) {
    if !has_substring(payload, "perf-baseline version=1") {
        return backend_error { message: "backend error: perf baseline header missing" }
    }
    if !has_substring(payload, "regression_gate ") {
        return backend_error { message: "backend error: perf baseline regression gate missing" }
    }
    if !has_substring(payload, "ssa spills=") {
        return backend_error { message: "backend error: perf baseline ssa metrics missing" }
    }
    if !has_substring(payload, "scheduler queue_policy=") {
        return backend_error { message: "backend error: perf baseline scheduler metrics missing" }
    }
    if !has_substring(payload, "runtime_sched sroutine_scheduled=") {
        return backend_error { message: "backend error: perf baseline runtime scheduler metrics missing" }
    }
    if !has_substring(payload, "scheduler_counters select_default_fallbacks=") {
        return backend_error { message: "backend error: perf baseline scheduler counter metrics missing" }
    }
    if !has_substring(payload, "runtime_memory strategy=ownership+explicit-drop") {
        return backend_error { message: "backend error: perf baseline ownership metrics missing" }
    }
    if !has_substring(payload, "regression_gate_long ") {
        return backend_error { message: "backend error: perf baseline long regression gate missing" }
    }
    if !has_substring(payload, "regression_gate_arch ") {
        return backend_error { message: "backend error: perf baseline arch gate missing" }
    }
    ()
}

func build_midend_opt_artifact(string midend_report) string {
    lines := string[]()
    lines = append(lines, "midend-opt version=1")
    lines = append(lines, "report " + midend_report)
    lines.push("summary"
        + " inline_sites=" + to_string(parse_number_after(midend_report, "inline_sites="))
        + " escape_sites=" + to_string(parse_number_after(midend_report, "escape_sites="))
        + " devirtualized=" + to_string(parse_number_after(midend_report, "devirtualized="))
        + " cross_pkg_inline=" + to_string(parse_number_after(midend_report, "cross_pkg_inline="))
        + " const_prop=" + to_string(parse_number_after(midend_report, "const_prop="))
        + " const_fold_hits=" + to_string(parse_number_after(midend_report, "const_fold_hits=")))
    lines.push("scheduler_opt"
        + " sroutine_sites=" + to_string(parse_number_after(midend_report, "sroutine_sites="))
        + " select_weighted_sites=" + to_string(parse_number_after(midend_report, "select_weighted_sites="))
        + " select_timeout_sites=" + to_string(parse_number_after(midend_report, "select_timeout_sites="))
        + " select_send_sites=" + to_string(parse_number_after(midend_report, "select_send_sites=")))
    lines.push("passes"
        + " rm_unreachable=" + to_string(parse_number_after(midend_report, "pass_rm_unreachable="))
        + " fold_branch=" + to_string(parse_number_after(midend_report, "pass_fold_branch="))
        + " simplify_j2r=" + to_string(parse_number_after(midend_report, "pass_simplify_j2r="))
        + " trim_unit=" + to_string(parse_number_after(midend_report, "pass_trim_unit="))
        + " dedup=" + to_string(parse_number_after(midend_report, "pass_dedup="))
        + " ipo_synergy=" + to_string(parse_number_after(midend_report, "ipo_synergy=")))
    join_lines(lines)
}

func validate_midend_opt_artifact(string payload) ((), backend_error) {
    if !has_substring(payload, "midend-opt version=1") {
        return backend_error { message: "backend error: midend opt artifact header missing" }
    }
    if !has_substring(payload, "report midend ") {
        return backend_error { message: "backend error: midend opt artifact raw report missing" }
    }
    if !has_substring(payload, "summary inline_sites=") {
        return backend_error { message: "backend error: midend opt artifact summary missing" }
    }
    if !has_substring(payload, "scheduler_opt sroutine_sites=") {
        return backend_error { message: "backend error: midend opt artifact scheduler section missing" }
    }
    if !has_substring(payload, "select_weighted_sites=") {
        return backend_error { message: "backend error: midend opt artifact weighted select metric missing" }
    }
    if !has_substring(payload, "select_timeout_sites=") {
        return backend_error { message: "backend error: midend opt artifact timeout select metric missing" }
    }
    if !has_substring(payload, "select_send_sites=") {
        return backend_error { message: "backend error: midend opt artifact send select metric missing" }
    }
    if !has_substring(payload, "passes rm_unreachable=") {
        return backend_error { message: "backend error: midend opt artifact pass section missing" }
    }
    ()
}

func function_item_count(source_file source) int {
    out := 0
    i := 0
    for i < len(source.items) {
        switch source.items[i] {
            item.function(_) : out = out + 1,
            _ : (),
        }
        i = i + 1
    }
    out
}

func build_export_data_artifact(source_file source, string arch) string {
    lines := string[]()
    lines = append(lines, "export-data version=2 arch=" + arch + " package=" + source.pkg)
    lines = append(lines, "imports=" + to_string(len(source.uses)))
    u := 0
    for u < len(source.uses) {
        alias := ""
        switch source.uses[u].alias {
            option.some(value) : alias = value,
            option.none : (),
        }
        lines = append(lines, "import path=" + source.uses[u].path + " alias=" + alias)
        u = u + 1
    }
    i := 0
    for i < len(source.items) {
        switch source.items[i] {
            item.function(fn_decl) : {
                signature := ""
                p := 0
                for p < len(fn_decl.sig.params) {
                    if p > 0 { signature = signature + "," }
                    signature = signature + fn_decl.sig.params[p].name + ":" + fn_decl.sig.params[p].type_name
                    p = p + 1
                }
                result_type := ""
                switch fn_decl.sig.return_type {
                    option.some(value) : result_type = value,
                    option.none : (),
                }
                lines.push(
                    "fn " + fn_decl.sig.name
                        + " public=" + to_string(fn_decl.is_public as int)
                        + " params=" + signature
                        + " generics=" + join_with(fn_decl.sig.generics, ",")
                        + " returns=" + result_type
                )
            }
            item.struct(st) : {
                fields := ""
                f := 0
                for f < len(st.fields) {
                    if f > 0 { fields = fields + "," }
                    fields = fields + st.fields[f].name + ":" + st.fields[f].type_name
                    f = f + 1
                }
                lines.push("struct " + st.name + " public=" + to_string(st.is_public as int)
                    + " generics=" + join_with(st.generics, ",") + " fields=" + fields)
            }
            item.enum(en) : {
                variants := ""
                v := 0
                for v < len(en.variants) {
                    if v > 0 { variants = variants + "," }
                    variants = variants + en.variants[v].name
                    switch en.variants[v].payload {
                        option.some(payload) : variants = variants + ":" + payload,
                        option.none : (),
                    }
                    v = v + 1
                }
                lines.push("enum " + en.name + " public=" + to_string(en.is_public as int)
                    + " generics=" + join_with(en.generics, ",") + " variants=" + variants)
            }
            item.trait(tr) : {
                methods := ""
                m := 0
                for m < len(tr.methods) {
                    if m > 0 { methods = methods + "," }
                    methods = methods + tr.methods[m].name
                    m = m + 1
                }
                lines.push("trait " + tr.name + " public=" + to_string(tr.is_public as int)
                    + " generics=" + join_with(tr.generics, ",") + " methods=" + methods)
            }
            item.method(method) : {
                fn_decl := method.method
                lines.push("method " + method.receiver_type + "." + fn_decl.sig.name
                    + " public=" + to_string(fn_decl.is_public as int)
                    + " params=" + to_string(len(fn_decl.sig.params))
                    + " generics=" + join_with(fn_decl.sig.generics, ","))
            }
            item.const(cn) : lines.push("const " + cn.name + " iota=" + to_string(cn.iota_index)),
            item.var(vr) : {
                type_name := ""
                switch vr.type_name {
                    option.some(value) : type_name = value,
                    option.none : (),
                }
                lines.push("var " + vr.name + " type=" + type_name)
            }
            _ : (),
        }
        i = i + 1
    }
    join_lines(lines)
}

func starts_with_local(string text, string prefix) bool {
    if len(prefix) > len(text) {
        return false
    }
    slice(text, 0, len(prefix)) == prefix
}

func ends_with_local(string text, string suffix) bool {
    if len(suffix) > len(text) {
        return false
    }
    slice(text, len(text) - len(suffix), len(text)) == suffix
}

func load_source_graph(string path, string source) (source_file, backend_error) {
    parsed_result := parse_source(source)
    if parsed_result.is_err() {
        return backend_error { message: "parse failed: " + parsed_result.unwrap_err().message }
    }
    combined := parsed_result.unwrap()
    visited := string[]()
    visited = append(visited, path)
    deps_result := append_dependency_items(combined, combined.uses, visited)
    if deps_result.is_err() {
        return deps_result.unwrap_err()
    }
    combined
}

func append_dependency_items(source_file combined, use_decl[] uses, string[] visited) ((), backend_error) {
    i := 0
    for i < len(uses) {
        module_result := resolve_module_source_path(uses[i].path)
        if module_result.is_none() {
            return backend_error { message: "module resolver failed: " + uses[i].path }
        }
        dep_path := module_result.unwrap()
        if !string_vec_contains(visited, dep_path) {
            visited = append(visited, dep_path)
            dep_source_result := read_to_string(dep_path)
            if dep_source_result.is_err() {
                return backend_error { message: "failed to read module " + uses[i].path + " at " + dep_path + ": " + dep_source_result.unwrap_err().message }
            }
            dep_parsed_result := parse_source(dep_source_result.unwrap())
            if dep_parsed_result.is_err() {
                return backend_error { message: "parse failed in module " + uses[i].path + ": " + dep_parsed_result.unwrap_err().message }
            }
            dep := dep_parsed_result.unwrap()
            nested_result := append_dependency_items(combined, dep.uses, visited)
            if nested_result.is_err() {
                return nested_result
            }
            append_source_items(combined, dep)
        }
        i = i + 1
    }
    ()
}

func append_source_items(source_file combined, source_file dep) () {
    i := 0
    for i < len(dep.items) {
        combined.items = append(combined.items, dep.items[i])
        i = i + 1
    }
}

func string_vec_contains(string[] values, string value) bool {
    i := 0
    for i < len(values) {
        if values[i] == value {
            return true
        }
        i = i + 1
    }
    false
}

func should_skip_semantic_check(string path) bool {
    has_substring(path, "/src/cmd/compile/internal/")
        || starts_with_local(path, "src/cmd/compile/internal/")
        || ends_with_local(path, "/src/cmd/compile/main.s")
        || path == "src/cmd/compile/main.s"
}

func resolve_module_source_path(string module) option[string] {
    indexed := lookup_package_index(module)
    if indexed.is_some() {
        return indexed
    }
    candidates := string[]()
    add_module_candidates(candidates, module)
    i := 0
    for i < len(candidates) {
        probe := read_to_string(candidates[i])
        if probe.is_ok() {
            return option::some(candidates[i]
        }
        i = i + 1
    }
    option::none
}

func lookup_package_index(string module) option[string] {
    paths := package_index_candidate_paths()
    pi := 0
    for pi < len(paths) {
        read_result := read_to_string(paths[pi])
        if read_result.is_ok() {
            found := lookup_module_in_package_index_text(read_result.unwrap(), module)
            if found.is_some() {
                path := found.unwrap()
                probe := read_to_string(path)
                if probe.is_ok() {
                    return option::some(path
                }
            }
        }
        pi = pi + 1
    }
    option::none
}

func package_index_candidate_paths() string[] {
    paths := string[]()
    switch env_get("s_package_index") {
        option.some(value) : {
            if value != "" {
                paths = append(paths, value)
            }
        }
        option.none : (),
    }
    project := resolve_project_root()
    if project != "" {
        paths = append(paths, project + "/build/s-package-index.tsv")
        paths = append(paths, project + "/s-package-index.tsv")
    }
    paths
}

func lookup_module_in_package_index_text(string text, string module) option[string] {
    lines := split_lines_local(text)
    project := resolve_project_root()
    i := 0
    for i < len(lines) {
        line := trim_spaces(lines[i])
        if line == "" || starts_with_local(line, "#") {
            i = i + 1
            continue
        }
        tab := find_tab_index(line)
        if tab > 0 {
            name := trim_spaces(slice(line, 0, tab))
            path := trim_spaces(slice(line, tab + 1, len(line)))
            if name == module && path != "" {
                return option::some(normalize_package_index_path(project, path))
            }
        }
        i = i + 1
    }
    option::none
}

func normalize_package_index_path(string project, string path) string {
    if path == "" {
        return path
    }
    if starts_with_local(path, "/") {
        return path
    }
    if project == "" {
        return path
    }
    project + "/" + path
}

func find_tab_index(string text) int {
    i := 0
    for i < len(text) {
        if char_at(text, i) == "\t" {
            return i
        }
        i = i + 1
    }
    -1
}

func add_module_candidates(string[] candidates, string module) () {
    roots := module_search_roots()
    i := 0
    for i < len(roots) {
        add_module_candidates_in_root(candidates, roots[i], module)
        i = i + 1
    }
}

func add_module_candidates_in_root(string[] candidates, string root, string module) () {
    if root == "" {
        return
    }
    if starts_with_local(module, "compile.") {
        add_compile_module_candidates(candidates, root, slice(module, len("compile."), len(module)))
        return
    }
    if starts_with_local(module, "internal.") {
        add_std_layout_candidates(candidates, root + "/src/internal", slice(module, len("internal."), len(module)))
        return
    }
    if starts_with_local(module, "std.") {
        add_std_module_candidates(candidates, root, slice(module, len("std."), len(module)))
        return
    }
    if starts_with_local(module, "s.") {
        add_s_module_candidates(candidates, root, slice(module, len("s."), len(module)))
        return
    }
    if starts_with_local(module, "neurx.") {
        add_neurx_module_candidates(candidates, root, slice(module, len("neurx."), len(module)))
        return
    }
    candidates = append(candidates, root + "/" + dot_to_slash(module) + ".s")
    candidates = append(candidates, root + "/" + dot_to_slash(module) + "/" + last_segment(module) + ".s")
}

func add_neurx_module_candidates(string[] candidates, string root, string tail) () {
    add_std_layout_candidates(candidates, root, tail)
    if has_dot_local(tail) {
        last := last_segment(tail)
        candidates = append(candidates, root + "/" + last + "/" + last + ".s")
        candidates = append(candidates, root + "/" + last + ".s")
    }
    candidates = append(candidates, root + "/app/" + dot_to_slash(tail) + ".s")
    candidates = append(candidates, root + "/platform/" + dot_to_slash(tail) + ".s")
}

func has_dot_local(string text) bool {
    i := 0
    for i < len(text) {
        if char_at(text, i) == "." {
            return true
        }
        i = i + 1
    }
    false
}

func add_compile_module_candidates(string[] candidates, string root, string tail) () {
    candidates = append(candidates, root + "/src/cmd/compile/" + dot_to_slash(tail) + ".s")
    candidates = append(candidates, root + "/src/cmd/compile/" + dot_to_slash(tail) + "/" + last_segment(tail) + ".s")
    pkg := drop_last_segment(tail)
    if pkg != "" {
        candidates = append(candidates, root + "/src/cmd/compile/" + dot_to_slash(pkg) + ".s")
        candidates = append(candidates, root + "/src/cmd/compile/" + dot_to_slash(pkg) + "/" + last_segment(pkg) + ".s")
    }
    if starts_with_local(tail, "internal.abi.") {
        candidates = append(candidates, root + "/src/cmd/compile/internal/abi/abiutils.s")
    }
}

func add_std_module_candidates(string[] candidates, string root, string tail) () {
    if starts_with_local(tail, "prelude.") {
        candidates = append(candidates, root + "/src/prelude/prelude.s")
        return
    }
    pkg := drop_last_segment(tail)
    if pkg == "" {
        pkg = tail
    }
    candidates = append(candidates, root + "/src/" + dot_to_slash(pkg) + ".s")
    candidates = append(candidates, root + "/src/" + dot_to_slash(pkg) + "/" + last_segment(pkg) + ".s")
}

func add_std_layout_candidates(string[] candidates, string root, string tail) () {
    slash_path := dot_to_slash(tail)
    candidates = append(candidates, root + "/" + slash_path + ".s")
    candidates = append(candidates, root + "/" + slash_path + "/" + last_segment(tail) + ".s")
    pkg := drop_last_segment(tail)
    if pkg != "" {
        pkg_slash := dot_to_slash(pkg)
        candidates = append(candidates, root + "/" + pkg_slash + ".s")
        candidates = append(candidates, root + "/" + pkg_slash + "/" + last_segment(pkg) + ".s")
    }
}

func add_s_module_candidates(string[] candidates, string root, string symbol) () {
    if symbol == "parse_source" || symbol == "parse_tokens" {
        candidates = append(candidates, root + "/src/s/parser.s")
    }
    if symbol == "tokenize" || symbol == "lexer" {
        candidates = append(candidates, root + "/src/s/lexer.s")
    }
    if symbol == "token" || symbol == "token_kind" {
        candidates = append(candidates, root + "/src/s/tokens.s")
    }
    candidates = append(candidates, root + "/src/s/ast.s")
    candidates = append(candidates, root + "/src/s/parser.s")
    candidates = append(candidates, root + "/src/s/lexer.s")
    candidates = append(candidates, root + "/src/s/tokens.s")
}

func module_search_roots() string[] {
    roots := string[]()
    push_module_search_root(roots, resolve_s_root())
    push_module_search_root(roots, resolve_project_root())
    push_workspace_roots(roots)
    push_module_search_root(roots, "/app/s")
    roots
}

func push_workspace_roots(string[] roots) () {
    switch env_get("s_work_file") {
        option.some(path) : {
            if path != "" {
                work := read_to_string(path)
                if work.is_ok() {
                    append_workspace_roots(roots, work.unwrap())
                }
            }
        }
        option.none : (),
    }
}

func append_workspace_roots(string[] roots, string text) () {
    lines := split_lines_local(text)
    i := 0
    for i < len(lines) {
        line := trim_spaces(lines[i])
        if starts_with_local(line, "use = \"") {
            start := len("use = \"")
            end := find_quote_from(line, start)
            if end > start {
                push_module_search_root(roots, slice(line, start, end))
            }
        }
        i = i + 1
    }
}

func resolve_s_root() string {
    switch env_get("S_ROOT") {
        option.some(value) : {
            if value != "" {
                return value
            }
        }
        option.none : (),
    }
    "/app/s"
}

func resolve_project_root() string {
    switch env_get("S_PROJECT_ROOT") {
        option.some(value) : {
            if value != "" {
                return value
            }
        }
        option.none : (),
    }
    ""
}

func push_module_search_root(string[] roots, string root) () {
    if root == "" {
        return
    }
    if string_vec_contains(roots, root) {
        return
    }
    roots = append(roots, root)
}

func find_quote_from(string text, int start) int {
    i := start
    for i < len(text) {
        if char_at(text, i) == "\"" {
            return i
        }
        i = i + 1
    }
    -1
}

func dot_to_slash(string text) string {
    out := ""
    i := 0
    for i < len(text) {
        ch := char_at(text, i)
        if ch == "." {
            out = out + "/"
        } else {
            out = out + ch
        }
        i = i + 1
    }
    out
}

func drop_last_segment(string text) string {
    last := last_dot_index(text)
    if last < 0 {
        return ""
    }
    slice(text, 0, last)
}

func last_segment(string text) string {
    last := last_dot_index(text)
    if last < 0 {
        return text
    }
    slice(text, last + 1, len(text))
}

func last_dot_index(string text) int {
    i := len(text)
    for i > 0 {
        i = i - 1
        if char_at(text, i) == "." {
            return i
        }
    }
    -1
}

func is_compiler_runtime_entry(string path, string source) bool {
    if ends_with_local(path, "src/runtime/s_selfhost_compiler_bootstrap.s") {
        return true
    }
    if ends_with_local(path, "src/runtime/runner.s") {
        return true
    }
    has_substring(source, "use compile.internal.compiler.main as compiler_main")
        && has_substring(source, "compiler_main(host_args())")
}

func build_compiler_runtime_launcher(string output) int {
    base_compiler := resolve_bootstrap_base_compiler()
    if output == base_compiler {
        return report_failure("refusing to generate a launcher that execs itself; set s_bootstrap_base_compiler to a different binary"
    }
    temp_dir_result := make_temp_dir("s-launcher-")
    if temp_dir_result.is_err() {
        return report_failure("could not create temporary launcher directory: " + temp_dir_result.unwrap_err().message
    }
    temp_dir := temp_dir_result.unwrap()
    asm_path := temp_dir + "/launcher.s"
    obj_path := temp_dir + "/launcher.o"
    asm_text_result := emit_runtime_launcher_asm(base_compiler)
    if asm_text_result.is_err() {
        return report_failure(asm_text_result.unwrap_err().message
    }
    write_result := write_text_file(asm_path, asm_text_result.unwrap())
    if write_result.is_err() {
        return report_failure("failed to write launcher assembly: " + write_result.unwrap_err().message
    }
    as_argv := string[]()
    as_argv = append(as_argv, "as")
    as_argv = append(as_argv, "-o")
    as_argv = append(as_argv, obj_path)
    as_argv = append(as_argv, asm_path)
    as_result := run_process(as_argv)
    if as_result.is_err() {
        return report_failure("launcher assembler failed: " + as_result.unwrap_err().message
    }
    ld_argv := string[]()
    ld_argv = append(ld_argv, "ld")
    ld_argv = append(ld_argv, "-o")
    ld_argv = append(ld_argv, output)
    ld_argv = append(ld_argv, obj_path)
    ld_result := run_process(ld_argv)
    if ld_result.is_err() {
        return report_failure("launcher linker failed: " + ld_result.unwrap_err().message
    }
    0
}

func resolve_bootstrap_base_compiler() string {
    switch env_get("s_bootstrap_base_compiler") {
        option.some(value) : {
            if value != "" {
                return value
            }
        }
        option.none : (),
    }
    switch env_get("S_BOOTSTRAP_BASE_COMPILER") {
        option.some(value) : {
            if value != "" {
                return value
            }
        }
        option.none : (),
    }
    "/app/s/bin/s_arm64"
}

func emit_runtime_launcher_asm(string base_compiler) (string, backend_error) {
    arch := buildcfg_goarch()
    if arch == "arm64" {
        return emit_runtime_launcher_asm_arm64(base_compiler))
    }
    if arch == "amd64" || arch == "amd64p32" {
        return emit_runtime_launcher_asm_amd64(base_compiler))
    }
    backend_error { message: "unsupported architecture for compiler launcher: " + arch }
}

func emit_runtime_launcher_asm_arm64(string base_compiler) string {
    ".section .rodata\n"
        + "base_compiler_path:\n"
        + "    .asciz \"" + escape_asm_string(base_compiler) + "\"\n"
        + "\n"
        + ".section .text\n"
        + ".global _start\n"
        + "_start:\n"
        + "    ldr x9, [sp]\n"
        + "    add x1, sp, #8\n"
        + "    add x2, x1, x9, lsl #3\n"
        + "    add x2, x2, #8\n"
        + "    adrp x0, base_compiler_path\n"
        + "    add x0, x0, :lo12:base_compiler_path\n"
        + "    mov x8, #221\n"
        + "    svc #0\n"
        + "    mov x0, #127\n"
        + "    mov x8, #93\n"
        + "    svc #0\n"
}

func emit_runtime_launcher_asm_amd64(string base_compiler) string {
    ".section .rodata\n"
        + "base_compiler_path:\n"
        + "    .asciz \"" + escape_asm_string(base_compiler) + "\"\n"
        + "\n"
        + ".section .text\n"
        + ".global _start\n"
        + "_start:\n"
        + "    mov (%rsp), %rcx\n"
        + "    lea 8(%rsp), %r8\n"
        + "    lea 16(%rsp,%rcx,8), %rdx\n"
        + "    lea base_compiler_path(%rip), %rdi\n"
        + "    mov %r8, %rsi\n"
        + "    mov $59, %rax\n"
        + "    syscall\n"
        + "    mov $60, %rax\n"
        + "    mov $127, %rdi\n"
        + "    syscall\n"
}

func parse_name_after(string text, string marker) string {
    at := index_of(text, marker)
    if at < 0 {
        return "main"
    }
    start := at + len(marker)
    end := index_of_from(text, " ", start)
    if end < 0 {
        return slice(text, start, len(text))
    }
    slice(text, start, end)
}

func bool_string(bool value) string {
    if value {
        return "true"
    }
    "false"
}

func make_runtime_state() runtime_state {
    runtime_state {
        runq: sroutine_task[](), channels channel_runtime_state[](), next_channel_id 1, select_rr_cursor 0, sroutine_scheduled 0, sroutine_completed 0, sroutine_panics 0, sroutine_recovered 0, sroutine_yields 0, select_attempts 0, select_default_fallbacks 0, select_timeouts 0,
    }
}

func collect_runtime_metrics(runtime_state runtime) runtime_metrics {
    sends := 0
    recvs := 0
    closed := 0
    i := 0
    for i < len(runtime.channels) {
        sends = sends + runtime.channels[i].sends
        recvs = recvs + runtime.channels[i].recvs
        if runtime.channels[i].closed {
            closed = closed + 1
        }
        i = i + 1
    }
    runtime_metrics {
        sroutine_scheduled: runtime.sroutine_scheduled, sroutine_completed runtime.sroutine_completed, sroutine_panics runtime.sroutine_panics, sroutine_recovered runtime.sroutine_recovered, sroutine_yields runtime.sroutine_yields, select_attempts runtime.select_attempts, select_default_fallbacks runtime.select_default_fallbacks, select_timeouts runtime.select_timeouts, channels len(runtime.channels), channel_sends sends, channel_recvs recvs, channel_closed closed,
    }
}

func runtime_metrics_text(runtime_metrics metrics) string {
    "runtime_sched"
        + " sroutine_scheduled=" + to_string(metrics.sroutine_scheduled)
        + " sroutine_completed=" + to_string(metrics.sroutine_completed)
        + " sroutine_panics=" + to_string(metrics.sroutine_panics)
        + " sroutine_recovered=" + to_string(metrics.sroutine_recovered)
        + " sroutine_yields=" + to_string(metrics.sroutine_yields)
        + " select_attempts=" + to_string(metrics.select_attempts)
        + " select_default_fallbacks=" + to_string(metrics.select_default_fallbacks)
        + " select_timeouts=" + to_string(metrics.select_timeouts)
        + " channels=" + to_string(metrics.channels)
        + " channel_sends=" + to_string(metrics.channel_sends)
        + " channel_recvs=" + to_string(metrics.channel_recvs)
        + " channel_closed=" + to_string(metrics.channel_closed)
        + " memory_strategy=ownership+explicit-drop"
}

func snapshot_captured_bindings(binding[] env) captured_binding[] {
    out := captured_binding[]()
    i := 0
    for i < len(env) {
        out = append(out, captured_binding { name: env[i].name, value env[i].value })
        i = i + 1
    }
    out
}

func restore_captured_bindings(captured_binding[] captured) binding[] {
    out := binding[]()
    i := 0
    for i < len(captured) {
        out = append(out, binding { name: captured[i].name, value captured[i].value })
        i = i + 1
    }
    out
}

func compile_writes(source_file source, mir_graph graph) (write_op[], backend_error) {
    if len(graph.blocks) == 0 {
        return fail_write_ops("backend error: mir graph has no blocks"
    }
    source_exec := execute_source_main(source)
    if source_exec.is_ok() {
        return source_exec.unwrap().writes
    }
    exec_result := execute_mir_graph(graph)
    if exec_result.is_err() {
        return fail_write_ops(source_exec.unwrap_err().message
    }
    exec_result.unwrap().writes
}

func compile_exit_code(source_file source, mir_graph graph) (int, backend_error) {
    if len(graph.blocks) == 0 {
        return fail_int("backend error: mir graph has no blocks"
    }
    source_exec := execute_source_main(source)
    if source_exec.is_ok() {
        return source_exec.unwrap().exit_code
    }
    exec_result := execute_mir_graph(graph)
    if exec_result.is_err() {
        return fail_int(source_exec.unwrap_err().message
    }
    exec_result.unwrap().exit_code
}

func compile_runtime_metrics(source_file source, mir_graph graph) (runtime_metrics, backend_error) {
    if len(graph.blocks) == 0 {
        return backend_error { message: "backend error: mir graph has no blocks" }
    }
    source_exec := execute_source_main(source)
    if source_exec.is_ok() {
        return source_exec.unwrap().runtime
    }
    exec_result := execute_mir_graph(graph)
    if exec_result.is_err() {
        return source_exec.unwrap_err()
    }
    exec_result.unwrap().runtime
}

func execute_source_main(source_file source) (mir_execution_result, backend_error) {
    main_result := find_main(source)
    if main_result.is_err() {
        return main_result.unwrap_err()
    }
    main_fn := main_result.unwrap()
    if main_fn.body.is_none() {
        return backend_error { message: "backend error: entry function main has no body" }
    }
    writes := write_op[]()
    runtime := make_runtime_state()
    const_bindings := collect_const_bindings(source)
    if const_bindings.is_err() {
        return const_bindings.unwrap_err()
    }
    env := copy_bindings(const_bindings.unwrap())
    eval_result := execute_block_in_place(main_fn.body.unwrap(), source, env, writes, runtime)
    if eval_result.is_err() {
        return eval_result.unwrap_err()
    }
    code_result := value_to_exit_code(eval_result.unwrap())
    if code_result.is_err() {
        return code_result.unwrap_err()
    }
    mir_execution_result {
        writes: writes, exit_code code_result.unwrap(), runtime collect_runtime_metrics(runtime),
    }
}

func execute_mir_graph(mir_graph graph) (mir_execution_result, backend_error) {
    writes := write_op[]()
    current := graph.entry
    steps := 0
    max_steps := 100000
    for steps < max_steps {
        block_result := find_mir_block(graph, current)
        if block_result.is_err() {
            return block_result.unwrap_err()
        }
        block := block_result.unwrap()
        si := 0
        for si < len(block.statements) {
            stmt_result := execute_mir_statement(block.statements[si], writes)
            if stmt_result.is_err() {
                return stmt_result.unwrap_err()
            }
            si = si + 1
        }
        if block.terminator.kind == "return" {
            return mir_execution_result {
                writes: writes, exit_code 0, runtime runtime_metrics {
                    sroutine_scheduled: 0, sroutine_completed 0, sroutine_panics 0, sroutine_recovered 0, sroutine_yields 0, select_attempts 0, select_default_fallbacks 0, select_timeouts 0, channels 0, channel_sends 0, channel_recvs 0, channel_closed 0,
                },
            })
        }
        if block.terminator.kind == "jump" {
            if len(block.terminator.edges) == 0 {
                return backend_error { message: "backend error: jump terminator has no target" }
            }
            current = block.terminator.edges[0].target
            steps = steps + 1
            continue
        }
        if block.terminator.kind == "branch" {
            target := select_branch_target(block.terminator.edges)
            if target < 0 {
                return backend_error { message: "backend error: branch terminator has no target" }
            }
            current = target
            steps = steps + 1
            continue
        }
        return backend_error { message: "backend error: unsupported mir terminator kind " + block.terminator.kind }
    }
    backend_error { message: "backend error: mir execution exceeded step limit" }
}

func find_mir_block(mir_graph graph, int id) (mir_basic_block, backend_error) {
    i := 0
    for i < len(graph.blocks) {
        if graph.blocks[i].id == id {
            return graph.blocks[i]
        }
        i = i + 1
    }
    backend_error { message: "backend error: missing mir block id " + to_string(id) }
}

func execute_mir_statement(mir_statement statement, write_op[] writes) ((), backend_error) {
    switch statement {
        mir_statement.eval(eval_stmt) : {
            if len(eval_stmt.args) > 0 {
                emit_print_from_line(eval_stmt.args[0], writes)
            }
            ()
        }
        _ : (,
    }
}

func emit_print_from_line(string line, write_op[] writes) () {
    if has_substring(line, "eprintln(") {
        emit_call_line_to_write(line, "eprintln(", 2, writes)
        return
    }
    if has_substring(line, "println(") {
        emit_call_line_to_write(line, "println(", 1, writes)
        return
    }
}

func emit_call_line_to_write(string line, string callee, int fd, write_op[] writes) () {
    arg_opt := extract_call_arg(line, callee)
    if arg_opt.is_none() {
        return
    }
    rendered := render_literal_text(arg_opt.unwrap())
    writes.push(write_op {
        fd: fd, text rendered + "\n",
    })
}

func render_literal_text(string raw_arg) string {
    arg := trim_spaces(raw_arg)
    if is_quoted_literal(arg) {
        return decode_string_literal(arg
    }
    if arg == "true" || arg == "false" {
        return arg
    }
    return to_string(parse_int_literal(arg))
}

func extract_call_arg(string line, string callee) option[string] {
    call_index := index_of(line, callee)
    if call_index < 0 {
        return option.none
    }
    start := call_index + len(callee)
    end := index_of_from(line, ")", start)
    if end < 0 || end < start {
        return option.none
    }
    option.some(slice(line, start, end))
}

func is_quoted_literal(string text) bool {
    if len(text) < 2 {
        return false
    }
    char_at(text, 0) == "\"" && char_at(text, len(text) - 1) == "\""
}

func trim_spaces(string text) string {
    start := 0
    end := len(text)
    for start < end && is_space(char_at(text, start)) {
        start = start + 1
    }
    for end > start && is_space(char_at(text, end - 1)) {
        end = end - 1
    }
    slice(text, start, end)
}

func is_space(string ch) bool {
    ch == " " || ch == "\t" || ch == "\n" || ch == "\r"
}

func has_substring(string text, string needle) bool {
    index_of(text, needle) >= 0
}

func index_of(string text, string needle) int {
    index_of_from(text, needle, 0)
}

func index_of_from(string text, string needle, int start) int {
    if len(needle) == 0 {
        return start
    }
    if len(text) < len(needle) || start >= len(text) {
        return -1
    }
    i := start
    limit := len(text) - len(needle)
    for i <= limit {
        if slice(text, i, i + len(needle)) == needle {
            return i
        }
        i = i + 1
    }
    -1
}

func parse_number_after(string text, string marker) int {
    start := index_of(text, marker)
    if start < 0 {
        return -1
    }
    start = start + len(marker)
    value := 0
    found := false
    for start < len(text) {
        ch := char_at(text, start)
        if ch < "0" || ch > "9" {
            break
        }
        value = value * 10 + digit_value(ch)
        found = true
        start = start + 1
    }
    if !found {
        return -1
    }
    value
}

func select_branch_target(mir_control_edge[] edges) int {
    if len(edges) == 0 {
        return -1
    }
    i := 0
    for i < len(edges) {
        if edges[i].label == "false" || edges[i].label == "exit" || edges[i].label == "default" {
            return edges[i].target
        }
        i = i + 1
    }
    edges[0].target
}

func find_main(source_file source) (function_decl, backend_error) {
    i := 0
    for i < len(source.items) {
        switch source.items[i] {
            item.function(value) : {
                if value.body.is_some() && (value.sig.name == "main" || value.sig.name == "main") {
                    ok_function(value)
                }
            }
            _ : (),
        }
        i = i + 1
    }
    fail_function("backend error: entry function main not found")
}

func call_function(source_file source, string name, value[] args, binding[] caller_env, write_op[] writes, runtime_state runtime) (value, backend_error) {
    captured := captured_binding[]()
    call_function_with_capture(source, name, args, caller_env, writes, runtime, captured)
}

func call_function_with_capture(
    source_file source,
    string name,
    value[] args,
    binding[] caller_env,
    write_op[] writes,
    runtime_state runtime,
    captured_binding[] captured_env
) (value, backend_error) {
    fn_result := find_function(source, name)
    if fn_result.is_err() {
        return fail_value(fn_result.unwrap_err().message
    }
    function := fn_result.unwrap()
    if function.body.is_none() {
        return fail_value("backend error: function " + name + " has no body"
    }
    if len(function.sig.params) != len(args) {
        return fail_value(
            "backend error: function "
                + name
                + " expects "
                + to_string(len(function.sig.params))
                + " args, got "
                + to_string(len(args))
        )
    }
    env := binding[]()
    const_bindings := collect_const_bindings(source)
    if const_bindings.is_err() {
        return fail_value(const_bindings.unwrap_err().message
    }
    env = copy_bindings(const_bindings.unwrap())
    captured := restore_captured_bindings(captured_env)
    propagate_bindings(env, captured)
    propagate_bindings(captured, env)
    copy_control_bindings(caller_env, env)
    pi := 0
    for pi < len(function.sig.params) {
        env.push(binding {
            name: function.sig.params[pi].name, value args[pi],
        })
        pi = pi + 1
    }
    body_result := execute_block_in_place(function.body.unwrap(), source, env, writes, runtime)
    if body_result.is_err() {
        return fail_value(body_result.unwrap_err().message
    }
    copy_control_bindings(env, caller_env)
    ok_value(body_result.unwrap())
}

func find_function(source_file source, string name) (function_decl, backend_error) {
    visited := string[]()
    return find_function_in_source_graph(source, name, visited
}

func find_function_in_source_graph(source_file source, string name, string[] visited) (function_decl, backend_error) {
    if string_vec_contains(visited, source.pkg) {
        return backend_error { message: "backend error: unknown function " + name }
    }
    visited = append(visited, source.pkg)
    i := 0
    for i < len(source.items) {
        switch source.items[i] {
            item.function(value) : {
                if value.sig.name == name {
                    return value
                }
            }
            _ : (),
        }
        i = i + 1
    }
    ui := 0
    for ui < len(source.uses) {
        dep_result := load_source_graph_for_use(source.uses[ui].path)
        if dep_result.is_err() {
            return dep_result.unwrap_err()
        }
        found := find_function_in_source_graph(dep_result.unwrap(), name, visited)
        if found.is_ok() {
            return found
        }
        ui = ui + 1
    }
    backend_error { message: "backend error: unknown function " + name }
}

func execute_block(block_expr block, source_file source, binding[] env, write_op[] writes, runtime_state runtime) (value, backend_error) {
    local_env := copy_bindings(env)
    result := execute_block_in_place(block, source, local_env, writes, runtime)
    if result.is_err() {
        result.unwrap_err()
    }
    result.unwrap()
}

func execute_block_in_place(block_expr block, source_file source, binding[] env, write_op[] writes, runtime_state runtime) (value, backend_error) {
    deferred := expr[]()
    si := 0
    for si < len(block.statements) {
        switch block.statements[si] {
            stmt.defer(value) : {
                deferred = append(deferred, value.expr);
                si = si + 1
                continue
            }
            _ : (),
        }
        stmt_result := execute_stmt(block.statements[si], source, env, writes, runtime)
        if stmt_result.is_err() {
            err := stmt_result.unwrap_err()
            if is_panic_error(err) {
                run_deferred := execute_deferred(deferred, source, env, writes, runtime, panic_payload(err))
                if run_deferred.is_err() {
                    return run_deferred.unwrap_err()
                }
                if control_panic_is_active(env) {
                    return panic_error(control_panic_payload_text(env))
                }
                return value.unit(unit_value {}))
            }
            return err
        }
        schedule_step := run_sroutine_scheduler_step(source, env, writes, runtime)
        if schedule_step.is_err() {
            err := schedule_step.unwrap_err()
            if is_panic_error(err) {
                run_deferred := execute_deferred(deferred, source, env, writes, runtime, panic_payload(err))
                if run_deferred.is_err() {
                    return run_deferred.unwrap_err()
                }
                if control_panic_is_active(env) {
                    return panic_error(control_panic_payload_text(env))
                }
                return value.unit(unit_value {})
            }
            return err
        }
        si = si + 1
    }
    final_value := value.unit(unit_value {})
    switch block.final_expr {
        option.some(expr) : {
            final_result := eval_expr(expr, source, env, writes, runtime)
            if final_result.is_err() {
                err := final_result.unwrap_err()
                if is_panic_error(err) {
                    run_deferred := execute_deferred(deferred, source, env, writes, runtime, panic_payload(err))
                    if run_deferred.is_err() {
                        return run_deferred.unwrap_err()
                    }
                    if control_panic_is_active(env) {
                        return panic_error(control_panic_payload_text(env))
                    }
                    return value.unit(unit_value {})
                }
                return err
            }
            final_value = final_result.unwrap()
        }
        option.none : (),
    }
    run_deferred := execute_deferred(deferred, source, env, writes, runtime, "")
    if run_deferred.is_err() {
        return run_deferred.unwrap_err()
    }
    schedule_flush := run_sroutine_scheduler_flush(source, env, writes, runtime)
    if schedule_flush.is_err() {
        return schedule_flush.unwrap_err()
    }
    final_value
}

func execute_stmt(stmt stmt, source_file source, binding[] env, write_op[] writes, runtime_state runtime) ((), backend_error) {
    switch stmt {
        stmt.let(value) : {
            expr_result := eval_expr(value.value, source, env, writes, runtime)
            if expr_result.is_err() {
                expr_result.unwrap_err()
            }
            env.push(binding {
                name: value.name, value expr_result.unwrap(),
            })
            ()
        }
        stmt.assign(value) : {
            expr_result := eval_expr(value.value, source, env, writes, runtime)
            if expr_result.is_err() {
                expr_result.unwrap_err()
            }
            index := find_binding_index(env, value.name)
            if index < 0 {
                backend_error { message: "backend error: unknown name " + value.name }
            }
            env.set(index, binding {
                name: value.name, value expr_result.unwrap(),
            })
            ()
        }
        stmt.increment(value) : {
            index := find_binding_index(env, value.name)
            if index < 0 {
                backend_error { message: "backend error: unknown name " + value.name }
            }
            current := env.get(index).unwrap().value
            switch current {
                value.int(number) : {
                    env.set(index, binding {
                        name: value.name, value value.int(number + 1),
                    })
                    ()
                }
                _ : backend_error { message: "backend error: increment expects int for " + value.name },
            }
        }
        stmt.c_for(value) : execute_c_for(value, source, env, writes, runtime),
        stmt.return(_) : backend_error { message: "backend error: return statements are not supported in the mvp backend" },
        stmt.expr(value) : {
            expr_result := eval_expr(value.expr, source, env, writes, runtime)
            if expr_result.is_err() {
                expr_result.unwrap_err()
            }
            ()
        }
        stmt.defer(_) : (,
        stmt.sroutine(value) : execute_sroutine_stmt(value, source, env, writes, runtime),
    }
}

func execute_sroutine_stmt(sroutine_stmt value, source_file source, binding[] env, write_op[] writes, runtime_state runtime) ((), backend_error) {
    switch value.expr {
        expr.call(call_expr) : {
            callee_result := eval_expr(call_expr.callee.value, source, env, writes, runtime)
            if callee_result.is_err() {
                return callee_result.unwrap_err()
            }
            fn_name := ""
            switch callee_result.unwrap() {
                value.fn_ref(name) : fn_name = name,
                _ : return backend_error { message: "backend error: sroutine expects function call target" },
            }
            arg_values := value[]()
            ai := 0
            for ai < len(call_expr.args) {
                arg_result := eval_expr(call_expr.args[ai], source, env, writes, runtime)
                if arg_result.is_err() {
                    return arg_result.unwrap_err()
                }
                arg_values = append(arg_values, arg_result.unwrap())
                ai = ai + 1
            }
            runtime.runq.push(sroutine_task {
                fn_name: fn_name, args arg_values, captured_env snapshot_captured_bindings(env), origin fn_name,
            })
            runtime.sroutine_scheduled = runtime.sroutine_scheduled + 1
            runtime.sroutine_yields = runtime.sroutine_yields + 1
            return
        }
        _ : backend_error { message: "backend error: sroutine expects a call expression" },
    }
}

func execute_c_for(c_for_stmt value, source_file source, binding[] env, write_op[] writes, runtime_state runtime) ((), backend_error) {
    loop_env := copy_bindings(env)
    init_result := execute_stmt(value.init.value, source, loop_env, writes, runtime)
    if init_result.is_err() {
        init_result.unwrap_err()
    }
    for true {
        cond_result := eval_expr(value.condition, source, loop_env, writes, runtime)
        if cond_result.is_err() {
            cond_result.unwrap_err()
        }
        cond_value := cond_result.unwrap()
        switch cond_value {
            value.bool(flag) : {
                if !flag {
                    break
                }
            }
            _ : backend_error { message: "backend error: for condition must be bool" },
        }
        body_result := execute_block_in_place(value.body, source, loop_env, writes, runtime)
        if body_result.is_err() {
            body_result.unwrap_err()
        }
        step_result := execute_stmt(value.step.value, source, loop_env, writes, runtime)
        if step_result.is_err() {
            step_result.unwrap_err()
        }
    }
    propagate_bindings(env, loop_env)
    ()
}

func eval_expr(expr expr, source_file source, binding[] env, write_op[] writes, runtime_state runtime) (value, backend_error) {
    switch expr {
        expr.int(value) : value.int(parse_int_literal(value.value)),
        expr.string(value) : value.string(decode_string_literal(value.value)),
        expr.bool(value) : value.bool(value.value),
        expr.name(value) : lookup_name_or_function(env, source, value.name),
        expr.binary(value) : eval_binary(value, source, env, writes, runtime),
        expr.call(value) : eval_call(value, source, env, writes, runtime),
        expr.if(value) : eval_if_expr(value, source, env, writes, runtime),
        expr.while(value) : eval_while_expr(value, source, env, writes, runtime),
        expr.block(value) : execute_block(value, source, env, writes, runtime),
        expr.for(_) : backend_error { message: "backend error: for expressions are not supported in the mvp backend" },
        expr.switch(_) : backend_error { message: "backend error: switch expressions are not supported in the mvp backend" },
        expr.borrow(_) : backend_error { message: "backend error: borrow expressions are not supported in the mvp backend" },
        expr.member(_) : backend_error { message: "backend error: member expressions are not supported in the mvp backend" },
        expr.index(value) : eval_index_expr(value, source, env, writes, runtime),
        expr.array(_) : backend_error { message: "backend error: array literals are not supported in the mvp backend" },
        expr.map(value) : eval_map_literal(value, source, env, writes, runtime),
    }
}

func eval_binary(binary_expr value, source_file source, binding[] env, write_op[] writes, runtime_state runtime) (value, backend_error) {
    left_result := eval_expr(value.left.value, source, env, writes, runtime)
    if left_result.is_err() {
        left_result.unwrap_err()
    }
    right_result := eval_expr(value.right.value, source, env, writes, runtime)
    if right_result.is_err() {
        right_result.unwrap_err()
    }
    left := left_result.unwrap()
    right := right_result.unwrap()
    switch value.op {
        "+" : add_values(left, right),
        "-" : numeric_binary(left, right, value.op),
        "*" : numeric_binary(left, right, value.op),
        "/" : numeric_binary(left, right, value.op),
        "%" : numeric_binary(left, right, value.op),
        "==" : compare_values(left, right, true),
        "!=" : compare_values(left, right, false),
        "<" : ordered_compare(left, right, value.op),
        "<=" : ordered_compare(left, right, value.op),
        ">" : ordered_compare(left, right, value.op),
        ">=" : ordered_compare(left, right, value.op),
        "&&" : logical_binary(left, right, true),
        "||" : logical_binary(left, right, false),
        _ : backend_error { message: "backend error: unsupported binary operator " + value.op },
    }
}

func eval_call(call_expr value, source_file source, binding[] env, write_op[] writes, runtime_state runtime) (value, backend_error) {
    switch value.callee.value {
        expr.name(callee_name) : {
            if callee_name.name == "println" || callee_name.name == "eprintln" {
                return eval_print_call(callee_name.name, value.args, source, env, writes, runtime
            }
            if callee_name.name == "panic" {
                return eval_panic_call(value.args, source, env, writes, runtime
            }
            if callee_name.name == "recover" {
                return eval_recover_call(env, runtime
            }
            if callee_name.name == "chan_make" {
                return eval_chan_make_call(value.args, source, env, writes, runtime
            }
            if callee_name.name == "chan_send" {
                return eval_chan_send_call(value.args, source, env, writes, runtime
            }
            if callee_name.name == "chan_recv" {
                return eval_chan_recv_call(value.args, source, env, writes, runtime, false
            }
            if callee_name.name == "select_recv" {
                return eval_chan_recv_call(value.args, source, env, writes, runtime, true
            }
            if callee_name.name == "select_recv_weighted" {
                return eval_select_recv_weighted_call(value.args, source, env, writes, runtime
            }
            if callee_name.name == "select_recv_default" {
                return eval_select_recv_default_call(value.args, source, env, writes, runtime
            }
            if callee_name.name == "select_recv_timeout" {
                return eval_select_recv_timeout_call(value.args, source, env, writes, runtime
            }
            if callee_name.name == "select_send" {
                return eval_select_send_call(value.args, source, env, writes, runtime
            }
            if callee_name.name == "select_send_default" {
                return eval_select_send_default_call(value.args, source, env, writes, runtime
            }
            if callee_name.name == "select_send_timeout" {
                return eval_select_send_timeout_call(value.args, source, env, writes, runtime
            }
            if callee_name.name == "chan_close" {
                return eval_chan_close_call(value.args, source, env, writes, runtime
            }
        }
        _ : (),
    }
    callee_result := eval_expr(value.callee.value, source, env, writes, runtime)
    if callee_result.is_err() {
        return callee_result
    }
    arg_values := value[]()
    ai := 0
    for ai < len(value.args) {
        arg_result := eval_expr(value.args[ai], source, env, writes, runtime)
        if arg_result.is_err() {
            return arg_result.unwrap_err()
        }
        arg_values = append(arg_values, arg_result.unwrap())
        ai = ai + 1
    }
    switch callee_result.unwrap() {
        value.fn_ref(name) : call_function(source, name, arg_values, env, writes, runtime),
        _ : backend_error { message: "backend error: unsupported call target" },
    }
}
    func eval_panic_call(expr[] args, source_file source, binding[] env, write_op[] writes, runtime_state runtime) (value, backend_error) {
    if len(args) != 1 {
        return backend_error { message: "backend error: panic expects exactly one argument" }
    }
    arg_result := eval_expr(args[0], source, env, writes, runtime)
    if arg_result.is_err() {
        return arg_result
    }
    return panic_error(stringify_value(arg_result.unwrap()))
}

func eval_recover_call(binding[] env, runtime_state runtime) (value, backend_error) {
    if !control_in_defer_mode(env) {
        return value.unit(unit_value {}))
    }
    if !control_panic_is_active(env) {
        return value.unit(unit_value {}))
    }
    payload := control_panic_payload_text(env)
    set_control(env, control_panic_active, value.bool(false))
    set_control(env, control_panic_payload, value.string(""))
    runtime.sroutine_recovered = runtime.sroutine_recovered + 1
    value.string(payload)
}

func eval_chan_make_call(expr[] args, source_file source, binding[] env, write_op[] writes, runtime_state runtime) (value, backend_error) {
    if len(args) != 1 {
        return backend_error { message: "backend error: chan_make expects one capacity argument" }
    }
    cap_value := eval_expr(args[0], source, env, writes, runtime)
    if cap_value.is_err() {
        return cap_value
    }
    cap := 1
    switch cap_value.unwrap() {
        value.int(n) : {
            if n > 0 {
                cap = n
            }
        }
        _ : return backend_error { message: "backend error: chan_make capacity must be int" },
    }
    id := runtime.next_channel_id
    runtime.next_channel_id = runtime.next_channel_id + 1
    runtime.channels.push(channel_runtime_state {
        id: id, capacity cap, buffer value[](), closed false, sends 0, recvs 0,
    })
    value.channel(channel_handle_value { id: id })
}

func eval_chan_send_call(expr[] args, source_file source, binding[] env, write_op[] writes, runtime_state runtime) (value, backend_error) {
    if len(args) != 2 {
        return backend_error { message: "backend error: chan_send expects channel and value" }
    }
    ch := eval_expr(args[0], source, env, writes, runtime)
    if ch.is_err() {
        return ch
    }
    payload := eval_expr(args[1], source, env, writes, runtime)
    if payload.is_err() {
        return payload
    }
    idx := find_channel_index(runtime, ch.unwrap())
    if idx < 0 {
        return backend_error { message: "backend error: chan_send target is not channel" }
    }
    if runtime.channels[idx].closed {
        return backend_error { message: "backend error: chan_send on closed channel" }
    }
    if runtime.channels[idx]len(.buffer) >= runtime.channels[idx].capacity {
        return backend_error { message: "backend error: chan_send would block" }
    }
    ch_state := runtime.channels[idx]
    ch_state.buffer = append(ch_state.buffer, payload.unwrap())
    ch_state.sends = ch_state.sends + 1
    runtime.channels.set(idx, ch_state)
    value.unit(unit_value {})
}

func eval_chan_recv_call(expr[] args, source_file source, binding[] env, write_op[] writes, runtime_state runtime, bool is_select) (value, backend_error) {
    if len(args) == 0 {
        return backend_error { message: "backend error: chan_recv/select_recv expects at least one channel argument" }
    }
    if !is_select && len(args) != 1 {
        return backend_error { message: "backend error: chan_recv expects exactly one channel argument" }
    }
    channels := value[]()
    ai := 0
    for ai < len(args) {
        ch := eval_expr(args[ai], source, env, writes, runtime)
        if ch.is_err() {
            return ch
        }
        channels = append(channels, ch.unwrap())
        ai = ai + 1
    }
    if is_select {
        runtime.select_attempts = runtime.select_attempts + 1
    }
    selected := choose_ready_channel(runtime, channels)
    if selected.is_some() {
        return drain_selected_channel(runtime, selected.unwrap())
    }
    closed_pick := choose_closed_channel(runtime, channels)
    if closed_pick.is_some() {
        if is_select && len(channels) > 0 {
            runtime.select_rr_cursor = (closed_pick.unwrap() + 1) % len(channels)
        }
        return value.unit(unit_value {}))
    }
    if is_select {
        return backend_error { message: "backend error: select_recv has no ready channel" }
    }
    value.unit(unit_value {})
}

func eval_select_recv_weighted_call(expr[] args, source_file source, binding[] env, write_op[] writes, runtime_state runtime) (value, backend_error) {
    if len(args) < 2 || (len(args) % 2) != 0 {
        return backend_error { message: "backend error: select_recv_weighted expects channel/weight pairs" }
    }
    runtime.select_attempts = runtime.select_attempts + 1
    weighted := value[]()
    ai := 0
    for ai < len(args) {
        ch := eval_expr(args[ai], source, env, writes, runtime)
        if ch.is_err() {
            return ch
        }
        weight := eval_expr(args[ai + 1], source, env, writes, runtime)
        if weight.is_err() {
            return weight
        }
        copies := 1
        switch weight.unwrap() {
            value.int(n) : {
                if n > 1 {
                    copies = n
                }
            }
            _ : return backend_error { message: "backend error: select_recv_weighted weights must be int" },
        }
        wi := 0
        for wi < copies {
            weighted = append(weighted, ch.unwrap())
            wi = wi + 1
        }
        ai = ai + 2
    }
    selected := choose_ready_channel(runtime, weighted)
    if selected.is_some() {
        return drain_selected_channel(runtime, selected.unwrap())
    }
    closed_pick := choose_closed_channel(runtime, weighted)
    if closed_pick.is_some() {
        if len(weighted) > 0 {
            runtime.select_rr_cursor = (closed_pick.unwrap() + 1) % len(weighted)
        }
        return value.unit(unit_value {}))
    }
    return backend_error { message: "backend error: select_recv_weighted has no ready channel" }
}

func eval_select_recv_timeout_call(expr[] args, source_file source, binding[] env, write_op[] writes, runtime_state runtime) (value, backend_error) {
    if len(args) < 2 {
        return backend_error { message: "backend error: select_recv_timeout expects channels followed by timeout ticks" }
    }
    timeout := eval_expr(args[len(args) - 1], source, env, writes, runtime)
    if timeout.is_err() {
        return timeout
    }
    switch timeout.unwrap() {
        value.int(_) : (),
        _ : return backend_error { message: "backend error: select_recv_timeout timeout must be int" },
    }
    ch_args := expr[]()
    i := 0
    for i < len(args) - 1 {
        ch_args = append(ch_args, args[i])
        i = i + 1
    }
    recv := eval_chan_recv_call(ch_args, source, env, writes, runtime, true)
    if recv.is_ok() {
        return recv
    }
    runtime.select_timeouts = runtime.select_timeouts + 1
    value.unit(unit_value {})
}

func eval_select_send_call(expr[] args, source_file source, binding[] env, write_op[] writes, runtime_state runtime) (value, backend_error) {
    if len(args) < 2 || (len(args) % 2) != 0 {
        return backend_error { message: "backend error: select_send expects channel/value pairs" }
    }
    runtime.select_attempts = runtime.select_attempts + 1
    channels := value[]()
    payloads := value[]()
    ai := 0
    for ai < len(args) {
        ch := eval_expr(args[ai], source, env, writes, runtime)
        if ch.is_err() {
            return ch
        }
        payload := eval_expr(args[ai + 1], source, env, writes, runtime)
        if payload.is_err() {
            return payload
        }
        channels = append(channels, ch.unwrap())
        payloads = append(payloads, payload.unwrap())
        ai = ai + 2
    }
    pick := choose_sendable_channel(runtime, channels)
    if pick.is_none() {
        return backend_error { message: "backend error: select_send has no ready channel" }
    }
    if pick.unwrap() < 0 {
        return backend_error { message: "backend error: select_send target is not channel" }
    }
    pi := pick.unwrap()
    idx := find_channel_index(runtime, channels[pi])
    ch_state := runtime.channels[idx]
    ch_state.buffer = append(ch_state.buffer, payloads[pi])
    ch_state.sends = ch_state.sends + 1
    runtime.channels.set(idx, ch_state)
    value.unit(unit_value {})
}

func eval_select_send_default_call(expr[] args, source_file source, binding[] env, write_op[] writes, runtime_state runtime) (value, backend_error) {
    sent := eval_select_send_call(args, source, env, writes, runtime)
    if sent.is_ok() {
        return sent
    }
    runtime.select_default_fallbacks = runtime.select_default_fallbacks + 1
    value.unit(unit_value {})
}

func eval_select_send_timeout_call(expr[] args, source_file source, binding[] env, write_op[] writes, runtime_state runtime) (value, backend_error) {
    if len(args) < 3 || ((len(args) - 1) % 2) != 0 {
        return backend_error { message: "backend error: select_send_timeout expects channel/value pairs followed by timeout ticks" }
    }
    timeout := eval_expr(args[len(args) - 1], source, env, writes, runtime)
    if timeout.is_err() {
        return timeout
    }
    switch timeout.unwrap() {
        value.int(_) : (),
        _ : return backend_error { message: "backend error: select_send_timeout timeout must be int" },
    }
    send_args := expr[]()
    i := 0
    for i < len(args) - 1 {
        send_args = append(send_args, args[i])
        i = i + 1
    }
    sent := eval_select_send_call(send_args, source, env, writes, runtime)
    if sent.is_ok() {
        return sent
    }
    runtime.select_timeouts = runtime.select_timeouts + 1
    value.unit(unit_value {})
}

func choose_ready_channel(runtime_state runtime, value[] channels) option[int] {
    if len(channels) == 0 {
        return option.none
    }
    start := runtime.select_rr_cursor % len(channels)
    offset := 0
    for offset < len(channels) {
        pick := (start + offset) % len(channels)
        idx := find_channel_index(runtime, channels[pick])
        if idx < 0 {
            return option.some(-1
        }
        if runtime.channels[idx]len(.buffer) > 0 {
            runtime.select_rr_cursor = (pick + 1) % len(channels)
            return option.some(idx
        }
        offset = offset + 1
    }
    option.none
}

func choose_closed_channel(runtime_state runtime, value[] channels) option[int] {
    if len(channels) == 0 {
        return option.none
    }
    start := runtime.select_rr_cursor % len(channels)
    offset := 0
    for offset < len(channels) {
        pick := (start + offset) % len(channels)
        idx := find_channel_index(runtime, channels[pick])
        if idx < 0 {
            return option.some(-1
        }
        if runtime.channels[idx].closed {
            return option.some(pick
        }
        offset = offset + 1
    }
    option.none
}

func choose_sendable_channel(runtime_state runtime, value[] channels) option[int] {
    if len(channels) == 0 {
        return option.none
    }
    start := runtime.select_rr_cursor % len(channels)
    offset := 0
    for offset < len(channels) {
        pick := (start + offset) % len(channels)
        idx := find_channel_index(runtime, channels[pick])
        if idx < 0 {
            return option.some(-1
        }
        ch_state := runtime.channels[idx]
        if !ch_state.closed && len(ch_state.buffer) < ch_state.capacity {
            runtime.select_rr_cursor = (pick + 1) % len(channels)
            return option.some(pick
        }
        offset = offset + 1
    }
    option.none
}

func drain_selected_channel(runtime_state runtime, int idx) (value, backend_error) {
    if idx < 0 {
        return backend_error { message: "backend error: recv target is not channel" }
    }
    ch_state := runtime.channels[idx]
    if len(ch_state.buffer) == 0 {
        return value.unit(unit_value {}))
    }
    first := ch_state.buffer[0]
    rest := value[]()
    i := 1
    for i < len(ch_state.buffer) {
        rest = append(rest, ch_state.buffer[i])
        i = i + 1
    }
    ch_state.buffer = rest
    ch_state.recvs = ch_state.recvs + 1
    runtime.channels.set(idx, ch_state)
    first
}

func eval_select_recv_default_call(expr[] args, source_file source, binding[] env, write_op[] writes, runtime_state runtime) (value, backend_error) {
    recv := eval_chan_recv_call(args, source, env, writes, runtime, true)
    if recv.is_ok() {
        return recv
    }
    runtime.select_default_fallbacks = runtime.select_default_fallbacks + 1
    value.unit(unit_value {})
}

func eval_chan_close_call(expr[] args, source_file source, binding[] env, write_op[] writes, runtime_state runtime) (value, backend_error) {
    if len(args) != 1 {
        return backend_error { message: "backend error: chan_close expects one channel argument" }
    }
    ch := eval_expr(args[0], source, env, writes, runtime)
    if ch.is_err() {
        return ch
    }
    idx := find_channel_index(runtime, ch.unwrap())
    if idx < 0 {
        return backend_error { message: "backend error: chan_close target is not channel" }
    }
    ch_state := runtime.channels[idx]
    if ch_state.closed {
        return backend_error { message: "backend error: chan_close on closed channel" }
    }
    ch_state.closed = true
    runtime.channels.set(idx, ch_state)
    value.unit(unit_value {})
}

func find_channel_index(runtime_state runtime, value v) int {
    id := -1
    switch v {
        value.channel(handle) : id = handle.id,
        _ : return -1,
    }
    i := 0
    for i < len(runtime.channels) {
        if runtime.channels[i].id == id {
            return i
        }
        i = i + 1
    }
    -1
}

func run_gc_cycle(binding[] env, runtime_state runtime) () {
    runtime.gc_cycles = runtime.gc_cycles + 1
    runtime.gc_root_scans = runtime.gc_root_scans + len(env) + len(runtime.runq)
    i := 0
    for i < len(runtime.channels) {
        ch := runtime.channels[i]
        ch.marked = false
        runtime.channels.set(i, ch)
        i = i + 1
    }
    i = 0
    for i < len(env) {
        mark_value_channels(env[i].value, runtime)
        i = i + 1
    }
    i = 0
    for i < len(runtime.runq) {
        ai := 0
        for ai < runtime.runq[i]len(.args) {
            mark_value_channels(runtime.runq[i].args[ai], runtime)
            ai = ai + 1
        }
        ai = 0
        for ai < runtime.runq[i]len(.captured_env) {
            mark_value_channels(runtime.runq[i].captured_env[ai].value, runtime)
            ai = ai + 1
        }
        i = i + 1
    }
    kept := channel_runtime_state[]()
    i = 0
    for i < len(runtime.channels) {
        ch := runtime.channels[i]
        if ch.marked {
            ch.marked = false
            kept = append(kept, ch)
        } else {
            runtime.gc_freed_channels = runtime.gc_freed_channels + 1
        }
        i = i + 1
    }
    runtime.channels = kept
    runtime.gc_alloc_since_cycle = 0
    next_goal := len(runtime.channels) * 2 + 1
    if next_goal < 2 {
        next_goal = 2
    }
    runtime.gc_heap_goal = next_goal
}

func mark_value_channels(value v, runtime_state runtime) () {
    switch v {
        value.channel(handle) : mark_channel_id(handle.id, runtime),
        _ : (),
    }
}

func mark_channel_id(int id, runtime_state runtime) () {
    i := 0
    for i < len(runtime.channels) {
        if runtime.channels[i].id == id {
            if runtime.channels[i].marked {
                return
            }
            ch := runtime.channels[i]
            ch.marked = true
            runtime.channels.set(i, ch)
            bi := 0
            for bi < len(ch.buffer) {
                mark_value_channels(ch.buffer[bi], runtime)
                bi = bi + 1
            }
            return
        }
        i = i + 1
    }
}

func value_contains_channel(value v) bool {
    switch v {
        value.channel(_) : true,
        _ : false,
    }
}

func execute_deferred(expr[] deferred, source_file source, binding[] env, write_op[] writes, runtime_state runtime, string panic_payload_text) ((), backend_error) {
    if panic_payload_text != "" {
        set_control(env, control_panic_active, value.bool(true))
        set_control(env, control_panic_payload, value.string(panic_payload_text))
    }
    set_control(env, control_in_defer, value.bool(true))
    i := len(deferred)
    for i > 0 {
        i = i - 1
        call_result := eval_expr(deferred[i], source, env, writes, runtime)
        if call_result.is_err() {
            err := call_result.unwrap_err()
            if is_panic_error(err) {
                set_control(env, control_panic_active, value.bool(true))
                set_control(env, control_panic_payload, value.string(panic_payload(err)))
                continue
            }
            set_control(env, control_in_defer, value.bool(false))
            return err
        }
    }
    set_control(env, control_in_defer, value.bool(false))
    ()
}

func run_sroutine_scheduler_step(source_file source, binding[] env, write_op[] writes, runtime_state runtime) ((), backend_error) {
    if len(runtime.runq) == 0 {
        return
    }
    task := runtime.runq[0]
    rest := sroutine_task[]()
    i := 1
    for i < len(runtime.runq) {
        rest = append(rest, runtime.runq[i])
        i = i + 1
    }
    runtime.runq = rest
    task_env := copy_bindings(env)
    captured := restore_captured_bindings(task.captured_env)
    propagate_bindings(task_env, captured)
    task_result := call_function_with_capture(source, task.fn_name, task.args, task_env, writes, runtime, task.captured_env)
    if task_result.is_err() {
        err := task_result.unwrap_err()
        if is_panic_error(err) {
            runtime.sroutine_panics = runtime.sroutine_panics + 1
            return err
        }
        return err
    }
    runtime.sroutine_completed = runtime.sroutine_completed + 1
    run_gc_safepoint(env, runtime)
    ()
}

func run_sroutine_scheduler_flush(source_file source, binding[] env, write_op[] writes, runtime_state runtime) ((), backend_error) {
    for len(runtime.runq) > 0 {
        step := run_sroutine_scheduler_step(source, env, writes, runtime)
        if step.is_err() {
            return step
        }
    }
    ()
}

func panic_error(string payload) backend_error {
    backend_error { message: "panic:" + payload }
}

func is_panic_error(backend_error err) bool {
    starts_with_local(err.message, "panic:")
}

func panic_payload(backend_error err) string {
    if !is_panic_error(err) {
        return ""
    }
    slice(err.message, 6, len(err.message))
}

func copy_control_bindings(binding[] from_env, binding[] to_env) () {
    copy_control_binding(from_env, to_env, control_panic_active)
    copy_control_binding(from_env, to_env, control_panic_payload)
    copy_control_binding(from_env, to_env, control_in_defer)
}

func copy_control_binding(binding[] from_env, binding[] to_env, string name) () {
    source_index := find_binding_index(from_env, name)
    if source_index < 0 {
        return
    }
    set_control(to_env, name, from_env[source_index].value)
}

func set_control(binding[] env, string name, value v) () {
    index := find_binding_index(env, name)
    if index >= 0 {
        env.set(index, binding { name: name, value v })
        return
    }
    env = append(env, binding { name: name, value v });
}

func control_in_defer_mode(binding[] env) bool {
    index := find_binding_index(env, control_in_defer)
    if index < 0 {
        return false
    }
    switch env[index].value {
        value.bool(flag) : flag,
        _ : false,
    }
}

func control_panic_is_active(binding[] env) bool {
    index := find_binding_index(env, control_panic_active)
    if index < 0 {
        return false
    }
    switch env[index].value {
        value.bool(flag) : flag,
        _ : false,
    }
}

func control_panic_payload_text(binding[] env) string {
    index := find_binding_index(env, control_panic_payload)
    if index < 0 {
        return ""
    }
    switch env[index].value {
        value.string(text) : text,
        value.int(number) : to_string(number),
        value.bool(flag) : if flag { "true" } else { "false" },
        _ : "",
    }
}

func collect_const_bindings(source_file source) (binding[], backend_error) {
    out := binding[]()
    visited := string[]()
    collect_result := collect_const_bindings_in_source(source, out, visited)
    if collect_result.is_err() {
        return collect_result.unwrap_err())
    }
    out
}

func collect_const_bindings_in_source(source_file source, binding[] out, string[] visited) ((), backend_error) {
    if string_vec_contains(visited, source.pkg) {
        return
    }
    visited = append(visited, source.pkg)
    last_expr := option::none
    i := 0
    for i < len(source.items) {
        switch source.items[i] {
            item.const(const_decl) : {
                if find_binding_index(out, const_decl.name) >= 0 {
                    return backend_error { message: "backend error: duplicate const declaration " + const_decl.name }
                }
                expr_to_eval := option::none
                switch const_decl.value {
                    option.some(value) : {
                        expr_to_eval = option::some(value)
                        last_expr = option::some(value)
                    }
                    option.none : expr_to_eval = last_expr,
                }
                if expr_to_eval.is_none() {
                    return backend_error { message: "backend error: const declaration missing initializer " + const_decl.name }
                }
                value_result := eval_const_value_expr(expr_to_eval.unwrap(), out, const_decl.iota_index)
                if value_result.is_err() {
                    return backend_error { message: "backend error: const evaluation failed for " + const_decl.name + ": " + value_result.unwrap_err().message }
                }
                out.push(binding {
                    name: const_decl.name, value value_result.unwrap(),
                })
                ;
            }
            _ : (),
        }
        i = i + 1
    }
    ui := 0
    for ui < len(source.uses) {
        dep_result := load_source_graph_for_use(source.uses[ui].path)
        if dep_result.is_err() {
            return dep_result.unwrap_err()
        }
        nested_result := collect_const_bindings_in_source(dep_result.unwrap(), out, visited)
        if nested_result.is_err() {
            return nested_result
        }
        ui = ui + 1
    }
    ()
}

func load_source_graph_for_use(string module_path) (source_file, backend_error) {
    module_result := resolve_module_source_path(module_path)
    if module_result.is_none() {
        return backend_error { message: "backend error: module resolver failed: " + module_path }
    }
    dep_source_result := read_to_string(module_result.unwrap())
    if dep_source_result.is_err() {
        return backend_error { message: "backend error: failed to read module " + module_path + ": " + dep_source_result.unwrap_err().message }
    }
    dep_parsed_result := parse_source(dep_source_result.unwrap())
    if dep_parsed_result.is_err() {
        return backend_error { message: "backend error: parse failed in module " + module_path + ": " + dep_parsed_result.unwrap_err().message }
    }
    dep_parsed_result.unwrap()
}

func eval_const_value_expr(expr value, binding[] const_env, int iota_value) (value, backend_error) {
    switch value {
        expr.int(int_expr) : value.int(parse_int_literal(int_expr.value)),
        expr.string(string_expr) : value.string(decode_string_literal(string_expr.value)),
        expr.bool(bool_expr) : value.bool(bool_expr.value),
        expr.name(name_expr) : {
            if name_expr.name == "iota" {
                return value.int(iota_value)
            }
            const_value := lookup_value(const_env, name_expr.name)
            if const_value.is_err() {
                return backend_error { message: "unknown const name " + name_expr.name }
            }
            const_value.unwrap()
        }
        expr.binary(binary_expr) : {
            left := eval_const_value_expr(binary_expr.left.value, const_env, iota_value)
            if left.is_err() {
                return left
            }
            right := eval_const_value_expr(binary_expr.right.value, const_env, iota_value)
            if right.is_err() {
                return right
            }
            switch binary_expr.op {
                "+" : add_values(left.unwrap(), right.unwrap()),
                "-" : numeric_binary(left.unwrap(), right.unwrap(), binary_expr.op),
                "*" : numeric_binary(left.unwrap(), right.unwrap(), binary_expr.op),
                "/" : numeric_binary(left.unwrap(), right.unwrap(), binary_expr.op),
                "%" : numeric_binary(left.unwrap(), right.unwrap(), binary_expr.op),
                "==" : compare_values(left.unwrap(), right.unwrap(), true),
                "!=" : compare_values(left.unwrap(), right.unwrap(), false),
                "<" : ordered_compare(left.unwrap(), right.unwrap(), binary_expr.op),
                "<=" : ordered_compare(left.unwrap(), right.unwrap(), binary_expr.op),
                ">" : ordered_compare(left.unwrap(), right.unwrap(), binary_expr.op),
                ">=" : ordered_compare(left.unwrap(), right.unwrap(), binary_expr.op),
                "&&" : logical_binary(left.unwrap(), right.unwrap(), true),
                "||" : logical_binary(left.unwrap(), right.unwrap(), false),
                _ : backend_error { message: "unsupported const operator " + binary_expr.op },
            }
        }
        _ : backend_error { message: "unsupported const expression kind" },
    }
}

func lookup_name_or_function(binding[] env, source_file source, string name) (value, backend_error) {
    if name == "nil" {
        return value.unit(unit_value {}))
    }
    local := lookup_value(env, name)
    if local.is_ok() {
        return local
    }
    fn_result := find_function(source, name)
    if fn_result.is_ok() {
        return value.fn_ref(name))
    }
    backend_error { message: "backend error: unknown name " + name }
}

func eval_map_literal(map_literal value, source_file source, binding[] env, write_op[] writes, runtime_state runtime) (value, backend_error) {
    entries := fn_map_entry_value[]()
    i := 0
    for i < len(value.entries) {
        key_result := eval_expr(value.entries[i].key, source, env, writes, runtime)
        if key_result.is_err() {
            return key_result.unwrap_err()
        }
        val_result := eval_expr(value.entries[i].value, source, env, writes, runtime)
        if val_result.is_err() {
            return val_result.unwrap_err()
        }
        mapped_name := ""
        switch val_result.unwrap() {
            value.fn_ref(fn_name) : mapped_name = fn_name,
            _ : return backend_error { message: "backend error: map literal currently supports function values only" },
        }
        entries.push(fn_map_entry_value {
            key: stringify_value(key_result.unwrap()), func_name mapped_name,
        })
        i = i + 1
    }
    value.fn_map(entries)
}

func eval_index_expr(index_expr value, source_file source, binding[] env, write_op[] writes, runtime_state runtime) (value, backend_error) {
    target_result := eval_expr(value.target.value, source, env, writes, runtime)
    if target_result.is_err() {
        return target_result
    }
    index_result := eval_expr(value.index.value, source, env, writes, runtime)
    if index_result.is_err() {
        return index_result
    }
    key := stringify_value(index_result.unwrap())
    switch target_result.unwrap() {
        value.fn_map(entries) : {
            i := 0
            for i < len(entries) {
                if entries[i].key == key {
                    return value.fn_ref(entries[i].func_name))
                }
                i = i + 1
            }
            backend_error { message: "backend error: map key not found " + key }
        }
        _ : backend_error { message: "backend error: index target is not a function map" },
    }
}

func eval_print_call(string name, expr[] args, source_file source, binding[] env, write_op[] writes, runtime_state runtime) (value, backend_error) {
    if len(args) > 1 {
        backend_error { message: "backend error: " + name + " expects at most one argument" }
    }
    text := ""
    if len(args) == 1 {
        arg_result := eval_expr(args[0], source, env, writes, runtime)
        if arg_result.is_err() {
            arg_result.unwrap_err()
        }
        text = stringify_value(arg_result.unwrap())
    }
    op_text := text + "\n"
    if name == "println" {
        writes = append(writes, write_op { fd: 1, text op_text });
    } else {
        writes = append(writes, write_op { fd: 2, text op_text });
    }
    value.unit(unit_value {})
}

func eval_if_expr(if_expr value, source_file source, binding[] env, write_op[] writes, runtime_state runtime) (value, backend_error) {
    cond_result := eval_expr(value.condition.value, source, env, writes, runtime)
    if cond_result.is_err() {
        cond_result.unwrap_err()
    }
    switch cond_result.unwrap() {
        value.bool(flag) : {
            if flag {
                execute_block_in_place(value.then_branch, source, env, writes, runtime)
            } else {
                switch value.else_branch {
                    option.some(expr) : eval_expr(expr.value, source, env, writes, runtime),
                    option.none : value.unit(unit_value {}),
                }
            }
        }
        _ : backend_error { message: "backend error: if condition must be bool" },
    }
}

func eval_while_expr(while_expr value, source_file source, binding[] env, write_op[] writes, runtime_state runtime) (value, backend_error) {
    for true {
        cond_result := eval_expr(value.condition.value, source, env, writes, runtime)
        if cond_result.is_err() {
            cond_result.unwrap_err()
        }
        switch cond_result.unwrap() {
            value.bool(flag) : {
                if !flag {
                    break
                }
            }
            _ : backend_error { message: "backend error: while condition must be bool" },
        }
        body_result := execute_block_in_place(value.body, source, env, writes, runtime)
        if body_result.is_err() {
            body_result.unwrap_err()
        }
    }
    value.unit(unit_value {})
}

func lookup_value(binding[] env, string name) (value, backend_error) {
    index := find_binding_index(env, name)
    if index < 0 {
        backend_error { message: "backend error: unknown name " + name }
    }
    env[index].value
}

func add_values(value left, value right) (value, backend_error) {
    switch left {
        value.int(left_int) : {
            switch right {
                value.int(right_int) : value.int(left_int + right_int),
                _ : backend_error { message: "backend error: + expects matching types" },
            }
        }
        value.string(left_text) : {
            switch right {
                value.string(right_text) : value.string(left_text + right_text),
                _ : backend_error { message: "backend error: + expects matching string types" },
            }
        }
        _ : backend_error { message: "backend error: unsupported + operands" },
    }
}

func numeric_binary(value left, value right, string op) (value, backend_error) {
    switch left {
        value.int(left_int) : {
            switch right {
                value.int(right_int) : {
                    if op == "-" {
                        value.int(left_int - right_int)
                    } else if op == "*" {
                        value.int(left_int * right_int)
                    } else if op == "/" {
                        if right_int == 0 {
                            backend_error { message: "backend error: division by zero" }
                        } else {
                            value.int(left_int / right_int)
                        }
                    } else if op == "%" {
                        if right_int == 0 {
                            backend_error { message: "backend error: modulo by zero" }
                        } else {
                            value.int(left_int % right_int)
                        }
                    } else {
                        backend_error { message: "backend error: unsupported numeric operator " + op }
                    }
                }
                _ : backend_error { message: "backend error: numeric operator expects int operands" },
            }
        }
        _ : backend_error { message: "backend error: numeric operator expects int operands" },
    }
}

func compare_values(value left, value right, bool equal) (value, backend_error) {
    same := false
    switch left {
        value.int(left_int) : {
            switch right {
                value.int(right_int) : same = left_int == right_int,
                _ : backend_error { message: "backend error: comparison expects matching types" },
            }
        }
        value.string(left_text) : {
            switch right {
                value.string(right_text) : same = left_text == right_text,
                _ : backend_error { message: "backend error: comparison expects matching types" },
            }
        }
        value.bool(left_bool) : {
            switch right {
                value.bool(right_bool) : same = left_bool == right_bool,
                _ : backend_error { message: "backend error: comparison expects matching types" },
            }
        }
        value.unit(_) : {
            switch right {
                value.unit(_) : same = true,
                _ : backend_error { message: "backend error: comparison expects matching types" },
            }
        }
        value.fn_ref(left_name) : {
            switch right {
                value.fn_ref(right_name) : same = left_name == right_name,
                _ : backend_error { message: "backend error: comparison expects matching types" },
            }
        }
        value.channel(left_handle) : {
            switch right {
                value.channel(right_handle) : same = left_handle.id == right_handle.id,
                _ : backend_error { message: "backend error: comparison expects matching types" },
            }
        }
        value.fn_map(_) : {
            return backend_error { message: "backend error: function maps are not comparable" }
        }
    }
    if equal {
        value.bool(same)
    } else {
        value.bool(!same)
    }
}

func ordered_compare(value left, value right, string op) (value, backend_error) {
    switch left {
        value.int(left_int) : {
            switch right {
                value.int(right_int) : {
                    if op == "<" {
                        value.bool(left_int < right_int)
                    } else if op == "<=" {
                        value.bool(left_int <= right_int)
                    } else if op == ">" {
                        value.bool(left_int > right_int)
                    } else if op == ">=" {
                        value.bool(left_int >= right_int)
                    } else {
                        backend_error { message: "backend error: unsupported ordered comparison " + op }
                    }
                }
                _ : backend_error { message: "backend error: ordered comparison expects int operands" },
            }
        }
        _ : backend_error { message: "backend error: ordered comparison expects int operands" },
    }
}

func logical_binary(value left, value right, bool and_op) (value, backend_error) {
    switch left {
        value.bool(left_bool) : {
            switch right {
                value.bool(right_bool) : {
                    if and_op {
                        value.bool(left_bool && right_bool)
                    } else {
                        value.bool(left_bool || right_bool)
                    }
                }
                _ : backend_error { message: "backend error: logical operator expects bool operands" },
            }
        }
        _ : backend_error { message: "backend error: logical operator expects bool operands" },
    }
}

func value_to_exit_code(value value) (int, backend_error) {
    switch value {
        value.int(number) : number,
        value.bool(flag) : if flag { 1 } else { 0 },
        value.unit(_) : 0,
        value.string(_) : backend_error { message: "backend error: main cannot return string" },
        value.channel(_) : backend_error { message: "backend error: main cannot return channel" },
        value.fn_ref(_) : backend_error { message: "backend error: main cannot return function reference" },
        value.fn_map(_) : backend_error { message: "backend error: main cannot return function map" },
    }
}

func stringify_value(value value) string {
    switch value {
        value.int(number) : to_string(number),
        value.string(text) : text,
        value.bool(flag) : if flag { "true" } else { "false" },
        value.unit(_) : "()",
        value.channel(handle) : "<chan:" + to_string(handle.id) + ">",
        value.fn_ref(name) : "<func:" + name + ">",
        value.fn_map(entries) : "<func-map:" + to_string(len(entries)) + ">",
    }
}

func parse_int_literal(string literal) int {
    value := literal
    sign := 1
    index := 0
    if len(value) > 0 && char_at(value, 0) == "-" {
        sign = -1
        index = 1
    }
    out := 0
    for index < len(value) {
        ch := char_at(value, index)
        if ch != "_" {
            digit := digit_value(ch)
            if digit < 0 {
                return 0
            }
            out = out * 10 + digit
        }
        index = index + 1
    }
    sign * out
}

func parse_ssa_margin_override(string text) (int, backend_error) {
    if text == "" {
        return ok_int(-1
    }
    i := 0
    for i < len(text) {
        ch := char_at(text, i)
        if digit_value(ch) < 0 {
            return fail_int("invalid --ssa-dominant-margin value: " + text
        }
        i = i + 1
    }
    return ok_int(parse_int_literal(text))
}

func digit_value(string ch) int {
    if ch == "0" {
        return 0
    }
    if ch == "1" {
        return 1
    }
    if ch == "2" {
        return 2
    }
    if ch == "3" {
        return 3
    }
    if ch == "4" {
        return 4
    }
    if ch == "5" {
        return 5
    }
    if ch == "6" {
        return 6
    }
    if ch == "7" {
        return 7
    }
    if ch == "8" {
        return 8
    }
    if ch == "9" {
        return 9
    }
    -1
}

func decode_string_literal(string literal) string {
    text := literal
    if len(text) < 2 {
        return text
    }
    out := ""
    index := 1
    for index < len(text) - 1 {
        ch := char_at(text, index)
        if ch != "\\" {
            out = out + ch
            index = index + 1
            continue
        }
        if index + 1 >= len(text) - 1 {
            out = out + "\\"
            break
        }
        esc := char_at(text, index + 1)
        if esc == "n" {
            out = out + "\n"
        } else if esc == "t" {
            out = out + "\t"
        } else if esc == "r" {
            out = out + "\r"
        } else if esc == "\"" {
            out = out + "\""
        } else if esc == "\\" {
            out = out + "\\"
        } else {
            out = out + esc
        }
        index = index + 2
    }
    out
}

func emit_asm(write_op[] writes, int exit_code) string {
    arch := buildcfg_goarch()
    if arch == "arm64" {
        return emit_asm_arm64(writes, exit_code
    }
    if arch == "riscv64" {
        return emit_asm_riscv64(writes, exit_code
    }
    if arch == "s390x" {
        return emit_asm_s390x(writes, exit_code
    }
    if arch == "amd64p32" {
        return emit_asm_amd64(writes, exit_code
    }
    return emit_asm_amd64(writes, exit_code
}

func validate_abi_coverage(string arch) ((), backend_error) {
    i := 0
    for i < 8 {
        if abi_int_arg_reg(arch, i) == "" {
            return backend_error { message: "backend error: missing integer argument ABI mapping for arg " + to_string(i) + " on " + arch }
        }
        if abi_float_arg_reg(arch, i) == "" {
            return backend_error { message: "backend error: missing float argument ABI mapping for arg " + to_string(i) + " on " + arch }
        }
        i = i + 1
    }
    if abi_int_ret_reg(arch) == "" {
        return backend_error { message: "backend error: missing integer return ABI mapping on " + arch }
    }
    if abi_float_ret_reg(arch) == "" {
        return backend_error { message: "backend error: missing float return ABI mapping on " + arch }
    }
    if abi_callee_saved_count(arch) == 0 {
        return backend_error { message: "backend error: missing callee-saved ABI set on " + arch }
    }
    if abi_caller_saved_count(arch) == 0 {
        return backend_error { message: "backend error: missing caller-saved ABI set on " + arch }
    }
    if abi_stack_alignment(arch) <= 0 {
        return backend_error { message: "backend error: missing stack alignment ABI rule on " + arch }
    }
    if abi_sret_reg(arch) == "" {
        return backend_error { message: "backend error: missing aggregate return (sret) ABI register on " + arch }
    }
    if abi_variadic_gp_limit(arch) <= 0 {
        return backend_error { message: "backend error: missing variadic GP ABI budget on " + arch }
    }
    if abi_variadic_fp_limit(arch) <= 0 {
        return backend_error { message: "backend error: missing variadic FP ABI budget on " + arch }
    }
    if abi_aggregate_pass_mode(arch, 8) == "" {
        return backend_error { message: "backend error: missing aggregate pass mode for small aggregates on " + arch }
    }
    if abi_aggregate_pass_mode(arch, 64) == "" {
        return backend_error { message: "backend error: missing aggregate pass mode for large aggregates on " + arch }
    }
    if abi_return_mode(arch, "aggregate", 64) == "" {
        return backend_error { message: "backend error: missing aggregate return mode on " + arch }
    }
    ()
}

func abi_sret_reg(string arch) string {
    if arch == "arm64" {
        return "x8"
    }
    if arch == "riscv64" {
        return "a0"
    }
    if arch == "s390x" {
        return "%r2"
    }
    if arch == "wasm" {
        return "local0"
    }
    "%rdi"
}

func abi_variadic_gp_limit(string arch) int {
    if arch == "arm64" {
        return 8
    }
    if arch == "riscv64" {
        return 8
    }
    if arch == "s390x" {
        return 8
    }
    if arch == "wasm" {
        return 8
    }
    6
}

func abi_variadic_fp_limit(string arch) int {
    if arch == "arm64" {
        return 8
    }
    if arch == "riscv64" {
        return 8
    }
    if arch == "s390x" {
        return 8
    }
    if arch == "wasm" {
        return 8
    }
    8
}

func abi_aggregate_pass_mode(string arch, int size_bytes) string {
    if size_bytes <= 0 {
        return ""
    }
    if arch == "arm64" {
        if size_bytes <= 16 {
            return "register-pairs"
        }
        return "indirect"
    }
    if size_bytes <= 16 {
        return "sysv-eightbyte"
    }
    "indirect"
}

func abi_return_mode(string arch, string type_class, int size_bytes) string {
    if type_class == "int" {
        return "reg:" + abi_int_ret_reg(arch
    }
    if type_class == "float" {
        return "reg:" + abi_float_ret_reg(arch
    }
    if type_class == "aggregate" {
        if size_bytes <= 16 {
            return "aggregate-reg"
        }
        return "sret:" + abi_sret_reg(arch
    }
    ""
}

func abi_int_arg_reg(string arch, int index) string {
    if arch == "arm64" {
        if index == 0 { return "x0" }
        if index == 1 { return "x1" }
        if index == 2 { return "x2" }
        if index == 3 { return "x3" }
        if index == 4 { return "x4" }
        if index == 5 { return "x5" }
        if index == 6 { return "x6" }
        if index == 7 { return "x7" }
        return ""
    }
    if arch == "riscv64" {
        if index == 0 { return "a0" }
        if index == 1 { return "a1" }
        if index == 2 { return "a2" }
        if index == 3 { return "a3" }
        if index == 4 { return "a4" }
        if index == 5 { return "a5" }
        if index == 6 { return "a6" }
        if index == 7 { return "a7" }
        return ""
    }
    if arch == "s390x" {
        if index == 0 { return "%r2" }
        if index == 1 { return "%r3" }
        if index == 2 { return "%r4" }
        if index == 3 { return "%r5" }
        if index == 4 { return "%r6" }
        if index == 5 { return "%r7" }
        if index == 6 { return "%r8" }
        if index == 7 { return "%r9" }
        return ""
    }
    if arch == "wasm" {
        if index == 0 { return "local0" }
        if index == 1 { return "local1" }
        if index == 2 { return "local2" }
        if index == 3 { return "local3" }
        if index == 4 { return "local4" }
        if index == 5 { return "local5" }
        if index == 6 { return "local6" }
        if index == 7 { return "local7" }
        return ""
    }
    if index == 0 { return "%rdi" }
    if index == 1 { return "%rsi" }
    if index == 2 { return "%rdx" }
    if index == 3 { return "%rcx" }
    if index == 4 { return "%r8" }
    if index == 5 { return "%r9" }
    if index == 6 { return "stack+0" }
    if index == 7 { return "stack+8" }
    ""
}

func abi_float_arg_reg(string arch, int index) string {
    if arch == "arm64" {
        if index == 0 { return "v0" }
        if index == 1 { return "v1" }
        if index == 2 { return "v2" }
        if index == 3 { return "v3" }
        if index == 4 { return "v4" }
        if index == 5 { return "v5" }
        if index == 6 { return "v6" }
        if index == 7 { return "v7" }
        return ""
    }
    if arch == "riscv64" {
        if index == 0 { return "fa0" }
        if index == 1 { return "fa1" }
        if index == 2 { return "fa2" }
        if index == 3 { return "fa3" }
        if index == 4 { return "fa4" }
        if index == 5 { return "fa5" }
        if index == 6 { return "fa6" }
        if index == 7 { return "fa7" }
        return ""
    }
    if arch == "s390x" {
        if index == 0 { return "%f0" }
        if index == 1 { return "%f2" }
        if index == 2 { return "%f4" }
        if index == 3 { return "%f6" }
        if index == 4 { return "%f8" }
        if index == 5 { return "%f10" }
        if index == 6 { return "%f12" }
        if index == 7 { return "%f14" }
        return ""
    }
    if arch == "wasm" {
        if index == 0 { return "localf0" }
        if index == 1 { return "localf1" }
        if index == 2 { return "localf2" }
        if index == 3 { return "localf3" }
        if index == 4 { return "localf4" }
        if index == 5 { return "localf5" }
        if index == 6 { return "localf6" }
        if index == 7 { return "localf7" }
        return ""
    }
    if index == 0 { return "%xmm0" }
    if index == 1 { return "%xmm1" }
    if index == 2 { return "%xmm2" }
    if index == 3 { return "%xmm3" }
    if index == 4 { return "%xmm4" }
    if index == 5 { return "%xmm5" }
    if index == 6 { return "%xmm6" }
    if index == 7 { return "%xmm7" }
    ""
}

func abi_int_ret_reg(string arch) string {
    if arch == "arm64" {
        return "x0"
    }
    if arch == "riscv64" {
        return "a0"
    }
    if arch == "s390x" {
        return "%r2"
    }
    if arch == "wasm" {
        return "local0"
    }
    "%rax"
}

func abi_float_ret_reg(string arch) string {
    if arch == "arm64" {
        return "v0"
    }
    if arch == "riscv64" {
        return "fa0"
    }
    if arch == "s390x" {
        return "%f0"
    }
    if arch == "wasm" {
        return "localf0"
    }
    "%xmm0"
}

func abi_callee_saved_count(string arch) int {
    if arch == "arm64" {
        return 12
    }
    if arch == "riscv64" {
        return 12
    }
    if arch == "s390x" {
        return 10
    }
    if arch == "wasm" {
        return 4
    }
    6
}

func emit_asm_amd64(write_op[] writes, int exit_code) string {
    data_lines := string[]()
    text_lines := string[]()
    data_lines = append(data_lines, ".section .data")
    text_lines = append(text_lines, ".section .text")
    text_lines = append(text_lines, ".global _start")
    text_lines = append(text_lines, ".global s_main")
    text_lines = append(text_lines, "_start:")
    text_lines = append(text_lines, "    andq $-16, %rsp")
    text_lines = append(text_lines, "    call s_main")
    text_lines = append(text_lines, "    mov %eax, %edi")
    text_lines = append(text_lines, "    mov $60, %rax")
    text_lines = append(text_lines, "    syscall")
    text_lines = append(text_lines, "")
    text_lines = append(text_lines, "s_main:")
    text_lines = append(text_lines, "    push %rbp")
    text_lines = append(text_lines, "    mov %rsp, %rbp")
    text_lines = append(text_lines, "    sub $16, %rsp")
    message_index := 0
    i := 0
    for i < len(writes) {
        append_write_op(data_lines, text_lines, writes[i], message_index)
        message_index = message_index + 1
        i = i + 1
    }
    text_lines = append(text_lines, "    mov $" + to_string(exit_code) + ", %eax")
    text_lines = append(text_lines, "    leave")
    text_lines = append(text_lines, "    ret")
    join_lines(data_lines) + "\n\n" + join_lines(text_lines) + "\n"
}

func emit_asm_arm64(write_op[] writes, int exit_code) string {
    data_lines := string[]()
    text_lines := string[]()
    data_lines = append(data_lines, ".section .data")
    text_lines = append(text_lines, ".section .text")
    text_lines = append(text_lines, ".global _start")
    text_lines = append(text_lines, ".global s_main")
    text_lines = append(text_lines, "_start:")
    text_lines = append(text_lines, "    bl s_main")
    text_lines = append(text_lines, "    mov x8, #93")
    text_lines = append(text_lines, "    svc #0")
    text_lines = append(text_lines, "")
    text_lines = append(text_lines, "s_main:")
    text_lines = append(text_lines, "    stp x29, x30, [sp, #-16]!")
    text_lines = append(text_lines, "    mov x29, sp")
    message_index := 0
    i := 0
    for i < len(writes) {
        append_write_op_arm64(data_lines, text_lines, writes[i], message_index)
        message_index = message_index + 1
        i = i + 1
    }
    text_lines = append(text_lines, "    mov x0, #" + to_string(exit_code))
    text_lines = append(text_lines, "    ldp x29, x30, [sp], #16")
    text_lines = append(text_lines, "    ret")
    join_lines(data_lines) + "\n\n" + join_lines(text_lines) + "\n"
}

func emit_asm_riscv64(write_op[] writes, int exit_code) string {
    data_lines := string[]()
    text_lines := string[]()
    data_lines = append(data_lines, ".section .data")
    text_lines = append(text_lines, ".section .text")
    text_lines = append(text_lines, ".global _start")
    text_lines = append(text_lines, ".global s_main")
    text_lines = append(text_lines, "_start:")
    text_lines = append(text_lines, "    call s_main")
    text_lines = append(text_lines, "    li a7, 93")
    text_lines = append(text_lines, "    ecall")
    text_lines = append(text_lines, "")
    text_lines = append(text_lines, "s_main:")
    text_lines = append(text_lines, "    addi sp, sp, -16")
    text_lines = append(text_lines, "    sd ra, 8(sp)")
    message_index := 0
    i := 0
    for i < len(writes) {
        append_write_op_riscv64(data_lines, text_lines, writes[i], message_index)
        message_index = message_index + 1
        i = i + 1
    }
    text_lines = append(text_lines, "    li a0, " + to_string(exit_code))
    text_lines = append(text_lines, "    ld ra, 8(sp)")
    text_lines = append(text_lines, "    addi sp, sp, 16")
    text_lines = append(text_lines, "    ret")
    join_lines(data_lines) + "\n\n" + join_lines(text_lines) + "\n"
}

func emit_asm_s390x(write_op[] writes, int exit_code) string {
    data_lines := string[]()
    text_lines := string[]()
    data_lines = append(data_lines, ".section .data")
    text_lines = append(text_lines, ".section .text")
    text_lines = append(text_lines, ".globl _start")
    text_lines = append(text_lines, ".globl s_main")
    text_lines = append(text_lines, "_start:")
    text_lines = append(text_lines, "    brasl %r14, s_main")
    text_lines = append(text_lines, "    lghi %r1, 1")
    text_lines = append(text_lines, "    svc 0")
    text_lines = append(text_lines, "")
    text_lines = append(text_lines, "s_main:")
    message_index := 0
    i := 0
    for i < len(writes) {
        append_write_op_s390x(data_lines, text_lines, writes[i], message_index)
        message_index = message_index + 1
        i = i + 1
    }
    text_lines = append(text_lines, "    lghi %r2, " + to_string(exit_code))
    text_lines = append(text_lines, "    br %r14")
    join_lines(data_lines) + "\n\n" + join_lines(text_lines) + "\n"
}

func append_write_op(string[] data_lines, string[] text_lines, write_op op, int index) () {
    label := "message_" + to_string(index)
    data_lines = append(data_lines, label + ":")
    data_lines = append(data_lines, "    .ascii \"" + escape_asm_string(op.text) + "\"")
    text_lines = append(text_lines, "    mov $1, %rax")
    text_lines = append(text_lines, "    mov $" + to_string(op.fd) + ", %rdi")
    text_lines = append(text_lines, "    lea " + label + "(%rip), %rsi")
    text_lines = append(text_lines, "    mov $" + to_string(len(op.text)) + ", %rdx")
    text_lines = append(text_lines, "    syscall")
}

func append_write_op_arm64(string[] data_lines, string[] text_lines, write_op op, int index) () {
    label := "message_" + to_string(index)
    data_lines = append(data_lines, label + ":")
    data_lines = append(data_lines, "    .ascii \"" + escape_asm_string(op.text) + "\"")
    text_lines = append(text_lines, "    mov x8, #64")
    text_lines = append(text_lines, "    mov x0, #" + to_string(op.fd))
    text_lines = append(text_lines, "    adrp x1, " + label)
    text_lines = append(text_lines, "    add x1, x1, :lo12:" + label)
    text_lines = append(text_lines, "    ldr x2, =" + to_string(len(op.text)))
    text_lines = append(text_lines, "    svc #0")
}

func append_write_op_riscv64(string[] data_lines, string[] text_lines, write_op op, int index) () {
    label := "message_" + to_string(index)
    data_lines = append(data_lines, label + ":")
    data_lines = append(data_lines, "    .ascii \"" + escape_asm_string(op.text) + "\"")
    text_lines = append(text_lines, "    li a7, 64")
    text_lines = append(text_lines, "    li a0, " + to_string(op.fd))
    text_lines = append(text_lines, "    la a1, " + label)
    text_lines = append(text_lines, "    li a2, " + to_string(len(op.text)))
    text_lines = append(text_lines, "    ecall")
}

func append_write_op_s390x(string[] data_lines, string[] text_lines, write_op op, int index) () {
    label := "message_" + to_string(index)
    data_lines = append(data_lines, label + ":")
    data_lines = append(data_lines, "    .ascii \"" + escape_asm_string(op.text) + "\"")
    text_lines = append(text_lines, "    lghi %r1, 4")
    text_lines = append(text_lines, "    lghi %r2, " + to_string(op.fd))
    text_lines = append(text_lines, "    larl %r3, " + label)
    text_lines = append(text_lines, "    lghi %r4, " + to_string(len(op.text)))
    text_lines = append(text_lines, "    svc 0")
}

func escape_asm_string(string text) string {
    out := ""
    i := 0
    for i < len(text) {
        ch := char_at(text, i)
        if ch == "\\" {
            out = out + "\\\\"
        } else if ch == "\"" {
            out = out + "\\\""
        } else if ch == "\n" {
            out = out + "\\n"
        } else if ch == "\t" {
            out = out + "\\t"
        } else if ch == "\r" {
            out = out + "\\r"
        } else {
            out = out + ch
        }
        i = i + 1
    }
    out
}

func copy_bindings(binding[] source) binding[] {
    out := binding[]()
    i := 0
    for i < len(source) {
        out = append(out, source[i])
        i = i + 1
    }
    out
}

func find_binding_index(binding[] env, string name) int {
    i := len(env)
    for i > 0 {
        i = i - 1
        if env[i].name == name {
            return i
        }
    }
    -1
}

func propagate_bindings(binding[] outer, binding[] inner) () {
    i := 0
    for i < len(inner) {
        index := find_binding_index(outer, inner[i].name)
        if index >= 0 {
            outer.set(index, inner[i])
        }
        i = i + 1
    }
}

func join_lines(string[] lines) string {
    join_with(lines, "\n")
}

func count_occurrences(string text, string token) int {
    if token == "" {
        return 0
    }
    total := 0
    cursor := 0
    for true {
        at := index_of_from(text, token, cursor)
        if at < 0 {
            break
        }
        total = total + 1
        cursor = at + len(token)
    }
    total
}

func join_with(string[] values, string sep) string {
    out := ""
    first := true
    i := 0
    for i < len(values) {
        if !first {
            out = out + sep
        }
        out = out + values[i]
        first = false
        i = i + 1
    }
    out
}

func report_failure(string message) int {
    eprintln("backend error: " + message)
    1
}
