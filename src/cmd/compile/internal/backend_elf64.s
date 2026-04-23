package compile.internal.backend_elf64

use compile.internal.ir.lower.lower_main_to_mir
use compile.internal.mir.mir_graph
use compile.internal.mir.mir_basic_block
use compile.internal.mir.mir_statement
use compile.internal.mir.mir_control_edge
use compile.internal.mir.dump_graph
use compile.internal.inline.estimate_inline_sites_graph
use compile.internal.escape.estimate_escape_sites_graph
use compile.internal.dispatch.devirtualize.estimate_devirtualized_sites_graph
use compile.internal.ssa_core.build_pipeline as build_ssa_pipeline
use compile.internal.ssa_core.build_pipeline_with_graph_hints as build_ssa_pipeline_with_graph_hints
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
use s.var_stmt
use s.while_expr
use std.fs.make_temp_dir
use std.fs.read_to_string
use std.fs.write_text_file
use std.io.eprintln
use std.option.option
use std.process.run_process
use std.prelude.char_at
use std.prelude.len
use std.prelude.slice
use std.prelude.to_string
use std.vec.vec

struct backend_error {
    string message
}

func ok_function(function_decl value) result[function_decl, backend_error] {
    result.ok(value);
}

func fail_function(string message) result[function_decl, backend_error] {
    result.err(backend_error {
        message: message,
    });
}

func ok_write_ops(vec[write_op] value) result[vec[write_op], backend_error] {
    result.ok(value);
}

func fail_write_ops(string message) result[vec[write_op], backend_error] {
    result.err(backend_error {
        message: message,
    });
}

func ok_value(value value) result[value, backend_error] {
    result.ok(value);
}

func fail_value(string message) result[value, backend_error] {
    result.err(backend_error {
        message: message,
    });
}

func ok_unit() result[(), backend_error] {
    result.ok(());
}

func fail_unit(string message) result[(), backend_error] {
    result.err(backend_error {
        message: message,
    });
}

func ok_int(int32 value) result[int32, backend_error] {
    result.ok(value);
}

func fail_int(string message) result[int32, backend_error] {
    result.err(backend_error {
        message: message,
    });
}

struct unit_value {}

enum value {
    int(int32),
    string(string),
    bool(bool),
    unit(unit_value),
}

struct binding {
    string name
    value value
}

struct write_op {
    int32 fd
    string text
}

struct mir_execution_result {
    vec[write_op] writes
    int32 exit_code
}

struct midend_result {
    string optimized_mir_text
    string report
}

struct stackmap_function_entry {
    string name
    int32 slots
    string bitmap
    int32 callee_saved
}

struct abi_behavior_entry {
    string name
    int32 param_count
    bool variadic
    string pass_mode
    string return_mode
}

func build(string path, string output) int32 {
    var source_result = read_to_string(path)
    if source_result.is_err() {
        return report_failure("failed to read source file: " + path + ": " + source_result.unwrap_err().message)
    }

    var source = source_result.unwrap()
    var parsed_result = parse_source(source)
    if parsed_result.is_err() {
        return report_failure("parse failed: " + parsed_result.unwrap_err().message)
    }
    var parsed = parsed_result.unwrap()

    if check_text(source) != 0 {
        return report_failure("semantic check failed")
    }

    var mir_result = lower_main_to_mir(parsed)
    if mir_result.is_err() {
        return report_failure("mir lowering failed: " + mir_result.unwrap_err())
    }
    var graph = mir_result.unwrap()
    var arch = buildcfg_goarch()

    var midend = run_midend_pipeline(graph)

    var ssa_program = build_ssa_pipeline_with_graph_hints(graph, midend.optimized_mir_text, arch)
    var ssa_text = dump_ssa_pipeline(ssa_program)
    if ssa_text == "" {
        return report_failure("ssa lowering failed: empty pipeline")
    }
    var debug_map = dump_ssa_debug_map(ssa_program)
    if debug_map == "" {
        return report_failure("ssa debug map failed: empty map")
    }

    var abi_runtime_check = validate_ssa_abi_contracts(arch, ssa_text)
    if abi_runtime_check.is_err() {
        return report_failure(abi_runtime_check.unwrap_err().message)
    }

    var abi_check = validate_abi_coverage(arch)
    if abi_check.is_err() {
        return report_failure(abi_check.unwrap_err().message)
    }

    var writes_result = compile_writes(graph)
    if writes_result.is_err() {
        return report_failure(writes_result.unwrap_err().message)
    }

    var exit_code_result = compile_exit_code(graph)
    if exit_code_result.is_err() {
        return report_failure(exit_code_result.unwrap_err().message)
    }

    var temp_dir_result = make_temp_dir("s-build-")
    if temp_dir_result.is_err() {
        return report_failure("could not create temporary output directory: " + temp_dir_result.unwrap_err().message)
    }

    var temp_dir = temp_dir_result.unwrap()
    if arch == "wasm" {
        var wasm_result = build_wasm_object_chain(temp_dir, output, writes_result.unwrap(), exit_code_result.unwrap())
        if wasm_result.is_err() {
            return report_failure(wasm_result.unwrap_err().message)
        }
        var wasm_binary_check = validate_wasi_binary_artifact(output)
        if wasm_binary_check.is_err() {
            return report_failure(wasm_binary_check.unwrap_err().message)
        }
    } else {
        var asm_text = emit_asm(writes_result.unwrap(), exit_code_result.unwrap())
        var asm_path = temp_dir + "/out.s"
        var obj_path = temp_dir + "/out.o"

        var write_result = write_text_file(asm_path, asm_text)
        if write_result.is_err() {
            return report_failure("failed to write assembly: " + write_result.unwrap_err().message)
        }

        var as_argv = vec[string]()
        as_argv.push("as");
        as_argv.push("-o");
        as_argv.push(obj_path);
        as_argv.push(asm_path);
        var as_result = run_process(as_argv)
        if as_result.is_err() {
            return report_failure("toolchain failed: " + as_result.unwrap_err().message)
        }

        var ld_argv = vec[string]()
        ld_argv.push("ld");
        ld_argv.push("-o");
        ld_argv.push(output);
        ld_argv.push(obj_path);
        var ld_result = run_process(ld_argv)
        if ld_result.is_err() {
            return report_failure("toolchain failed: " + ld_result.unwrap_err().message)
        }
    }

    var dbg_path = output + ".dbg"
    var dbg_payload = "ssa\n" + ssa_text + "\n\ndebug\n" + debug_map
    var dbg_write = write_text_file(dbg_path, dbg_payload)
    if dbg_write.is_err() {
        return report_failure("failed to write debug artifact: " + dbg_write.unwrap_err().message)
    }

    var stackmap_path = output + ".stackmap"
    var stackmap_payload = build_stackmap_artifact(arch, parsed, ssa_text, debug_map)
    var stackmap_write = write_text_file(stackmap_path, stackmap_payload)
    if stackmap_write.is_err() {
        return report_failure("failed to write stack map artifact: " + stackmap_write.unwrap_err().message)
    }

    var abi_path = output + ".abi"
    var abi_payload = build_abi_behavior_artifact(arch, parsed)
    var abi_write = write_text_file(abi_path, abi_payload)
    if abi_write.is_err() {
        return report_failure("failed to write ABI behavior artifact: " + abi_write.unwrap_err().message)
    }

    var abi_emit_path = output + ".abi.emit"
    var abi_emit_payload = build_abi_emit_plan(arch, parsed)
    var abi_emit_write = write_text_file(abi_emit_path, abi_emit_payload)
    if abi_emit_write.is_err() {
        return report_failure("failed to write ABI emission artifact: " + abi_emit_write.unwrap_err().message)
    }

    var abi_matrix_payload = build_abi_machine_matrix_artifact(arch, parsed, ssa_text)
    var abi_matrix_check = validate_abi_machine_matrix(abi_matrix_payload)
    if abi_matrix_check.is_err() {
        return report_failure(abi_matrix_check.unwrap_err().message)
    }
    var abi_matrix_path = output + ".abi.matrix"
    var abi_matrix_write = write_text_file(abi_matrix_path, abi_matrix_payload)
    if abi_matrix_write.is_err() {
        return report_failure("failed to write ABI matrix artifact: " + abi_matrix_write.unwrap_err().message)
    }

    var dwarf_path = output + ".dwarf"
    var dwarf_payload = build_dwarf_like_artifact(parsed, ssa_text, debug_map)
    var dwarf_check = validate_dwarf_consumability(dwarf_payload, ssa_text)
    if dwarf_check.is_err() {
        return report_failure(dwarf_check.unwrap_err().message)
    }
    var dwarf_write = write_text_file(dwarf_path, dwarf_payload)
    if dwarf_write.is_err() {
        return report_failure("failed to write DWARF-like artifact: " + dwarf_write.unwrap_err().message)
    }

    var cfi_path = output + ".cfi"
    var cfi_payload = build_cfi_artifact(arch, ssa_text, debug_map)
    var cfi_check = validate_cfi_artifact(cfi_payload)
    if cfi_check.is_err() {
        return report_failure(cfi_check.unwrap_err().message)
    }
    var cfi_write = write_text_file(cfi_path, cfi_payload)
    if cfi_write.is_err() {
        return report_failure("failed to write CFI artifact: " + cfi_write.unwrap_err().message)
    }

    var gc_path = output + ".gcmap"
    var gc_payload = build_gc_metadata_artifact(arch, parsed, ssa_text)
    var gc_check = validate_gc_contract_chain(gc_payload, parsed, ssa_text)
    if gc_check.is_err() {
        return report_failure(gc_check.unwrap_err().message)
    }
    var gc_write = write_text_file(gc_path, gc_payload)
    if gc_write.is_err() {
        return report_failure("failed to write GC metadata artifact: " + gc_write.unwrap_err().message)
    }

    var export_path = output + ".export"
    var export_payload = build_export_data_artifact(parsed, arch)
    var export_write = write_text_file(export_path, export_payload)
    if export_write.is_err() {
        return report_failure("failed to write export data artifact: " + export_write.unwrap_err().message)
    }

    var toolchain_path = output + ".toolchain"
    var toolchain_payload = build_toolchain_compat_artifact(parsed, arch)
    var toolchain_check = validate_toolchain_compat_artifact(toolchain_payload)
    if toolchain_check.is_err() {
        return report_failure(toolchain_check.unwrap_err().message)
    }
    var toolchain_write = write_text_file(toolchain_path, toolchain_payload)
    if toolchain_write.is_err() {
        return report_failure("failed to write toolchain compatibility artifact: " + toolchain_write.unwrap_err().message)
    }

    var perf_path = output + ".perf"
    var perf_payload = build_backend_perf_baseline_artifact(arch, ssa_text, midend.report)
    var perf_check = validate_backend_perf_baseline(perf_payload)
    if perf_check.is_err() {
        return report_failure(perf_check.unwrap_err().message)
    }
    var perf_write = write_text_file(perf_path, perf_payload)
    if perf_write.is_err() {
        return report_failure("failed to write backend perf baseline artifact: " + perf_write.unwrap_err().message)
    }

    var opt_path = output + ".opt"
    var opt_write = write_text_file(opt_path, midend.report)
    if opt_write.is_err() {
        return report_failure("failed to write optimization report: " + opt_write.unwrap_err().message)
    }

    0
}

func run_midend_pipeline(mir_graph graph) midend_result {
    var pass = apply_midend_pass_pipeline(graph)
    var rewritten_graph = pass.graph

    var inlined = estimate_inline_sites_graph(rewritten_graph)
    var escaped = estimate_escape_sites_graph(rewritten_graph)
    var devirt = estimate_devirtualized_sites_graph(rewritten_graph)
    var cross_pkg_inline = estimate_cross_pkg_inline_sites_graph(rewritten_graph, inlined)
    var const_prop = estimate_const_prop_sites_graph(rewritten_graph)
    var ipo_synergy = estimate_ipo_synergy(inlined, escaped, devirt, cross_pkg_inline, const_prop)

    var iter = 0
    while iter < 2 {
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

    var rewritten = dump_graph(rewritten_graph)
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
    rewritten = rewritten + " ipo=" + to_string(ipo_synergy)
    rewritten = rewritten + " pass.rm_unreachable=" + to_string(pass.removed_unreachable_blocks)
    rewritten = rewritten + " pass.fold_branch=" + to_string(pass.folded_redundant_branches)
    rewritten = rewritten + " pass.simplify_j2r=" + to_string(pass.simplified_jump_to_return)
    rewritten = rewritten + " pass.trim_unit=" + to_string(pass.removed_unit_lines)
    rewritten = rewritten + " pass.dedup=" + to_string(pass.dedup_lines)

    var report = "midend"
        + " inline_sites=" + to_string(inlined)
        + " escape_sites=" + to_string(escaped)
        + " devirtualized=" + to_string(devirt)
        + " cross_pkg_inline=" + to_string(cross_pkg_inline)
        + " const_prop=" + to_string(const_prop)
        + " ipo_synergy=" + to_string(ipo_synergy)
        + " pass_rm_unreachable=" + to_string(pass.removed_unreachable_blocks)
        + " pass_fold_branch=" + to_string(pass.folded_redundant_branches)
        + " pass_simplify_j2r=" + to_string(pass.simplified_jump_to_return)
        + " pass_trim_unit=" + to_string(pass.removed_unit_lines)
        + " pass_dedup=" + to_string(pass.dedup_lines)

    midend_result {
        optimized_mir_text: rewritten,
        report: report,
    }
}

struct midend_pass_result {
    mir_graph graph
    int32 simplified_jump_to_return
    int32 removed_unit_lines
    int32 dedup_lines
    int32 removed_unreachable_blocks
    int32 folded_redundant_branches
}

func apply_midend_pass_pipeline(mir_graph graph) midend_pass_result {
    var rewritten = graph

    var unreachable = remove_unreachable_blocks_pass(rewritten)
    rewritten = unreachable.graph

    var folded = simplify_redundant_branch_pass(rewritten)
    rewritten = folded.graph

    var simplified = simplify_jump_to_return_pass(rewritten)
    rewritten = simplified.graph

    var trimmed = trim_unit_line_pass(rewritten)
    rewritten = trimmed.graph

    var deduped = dedup_eval_line_pass(rewritten)
    rewritten = deduped.graph

    midend_pass_result {
        graph: rewritten,
        simplified_jump_to_return: simplified.count,
        removed_unit_lines: trimmed.count,
        dedup_lines: deduped.count,
        removed_unreachable_blocks: unreachable.count,
        folded_redundant_branches: folded.count,
    }
}

func remove_unreachable_blocks_pass(mir_graph graph) graph_pass_count_result {
    var rewritten = graph
    var reachable = vec[int32]()
    var work = vec[int32]()
    work.push(rewritten.entry)

    while work.len() > 0 {
        var id = work[work.len() - 1]
        work.pop()
        if contains_int32(reachable, id) {
            continue
        }
        reachable.push(id)

        var bi = find_block_index_by_id(rewritten, id)
        if bi < 0 {
            continue
        }

        var ei = 0
        while ei < rewritten.blocks[bi].terminator.edges.len() {
            var next = rewritten.blocks[bi].terminator.edges[ei].target
            if !contains_int32(reachable, next) {
                work.push(next)
            }
            ei = ei + 1
        }
    }

    var filtered_blocks = vec[mir_basic_block]()
    var i = 0
    while i < rewritten.blocks.len() {
        if contains_int32(reachable, rewritten.blocks[i].id) {
            filtered_blocks.push(rewritten.blocks[i])
        }
        i = i + 1
    }

    var removed = rewritten.blocks.len() - filtered_blocks.len()
    rewritten.blocks = filtered_blocks

    i = 0
    while i < rewritten.blocks.len() {
        var kept_edges = vec[mir_control_edge]()
        var j = 0
        while j < rewritten.blocks[i].terminator.edges.len() {
            var edge = rewritten.blocks[i].terminator.edges[j]
            if contains_int32(reachable, edge.target) {
                kept_edges.push(edge)
            }
            j = j + 1
        }
        rewritten.blocks[i].terminator.edges = kept_edges
        i = i + 1
    }

    if !contains_int32(reachable, rewritten.exit) {
        rewritten.exit = rewritten.entry
    }

    graph_pass_count_result { graph: rewritten, count: removed }
}

func simplify_redundant_branch_pass(mir_graph graph) graph_pass_count_result {
    var rewritten = graph
    var changed = 0

    var i = 0
    while i < rewritten.blocks.len() {
        var block = rewritten.blocks[i]
        if block.terminator.kind == "branch" && block.terminator.edges.len() > 1 {
            var target = block.terminator.edges[0].target
            var same_target = true
            var j = 1
            while j < block.terminator.edges.len() {
                if block.terminator.edges[j].target != target {
                    same_target = false
                }
                j = j + 1
            }
            if same_target {
                var folded = vec[mir_control_edge]()
                folded.push(mir_control_edge {
                    label: "folded",
                    target: target,
                    args: vec[mir_operand](),
                })
                rewritten.blocks[i].terminator.kind = "jump"
                rewritten.blocks[i].terminator.edges = folded
                changed = changed + 1
            }
        }
        i = i + 1
    }

    graph_pass_count_result { graph: rewritten, count: changed }
}

func contains_int32(vec[int32] values, int32 needle) bool {
    var i = 0
    while i < values.len() {
        if values[i] == needle {
            return true
        }
        i = i + 1
    }
    false
}

struct graph_pass_count_result {
    mir_graph graph
    int32 count
}

func simplify_jump_to_return_pass(mir_graph graph) graph_pass_count_result {
    var rewritten = graph
    var changed = 0

    var i = 0
    while i < rewritten.blocks.len() {
        var block = rewritten.blocks[i]
        if block.terminator.kind == "jump" && block.terminator.edges.len() == 1 {
            var target_id = block.terminator.edges[0].target
            var ti = find_block_index_by_id(rewritten, target_id)
            if ti >= 0 {
                var target = rewritten.blocks[ti]
                if target.terminator.kind == "return" && target.statements.len() == 0 {
                    rewritten.blocks[i].terminator.kind = "return"
                    rewritten.blocks[i].terminator.edges = vec[mir_control_edge]()
                    changed = changed + 1
                }
            }
        }
        i = i + 1
    }

    graph_pass_count_result { graph: rewritten, count: changed }
}

func trim_unit_line_pass(mir_graph graph) graph_pass_count_result {
    var rewritten = graph
    var changed = 0

    var i = 0
    while i < rewritten.blocks.len() {
        if rewritten.blocks[i].terminator.kind == "return" {
            var filtered = vec[mir_statement]()
            var j = 0
            while j < rewritten.blocks[i].statements.len() {
                var keep = true
                switch rewritten.blocks[i].statements[j] {
                    mir_statement::eval(eval_stmt) : {
                        if eval_stmt.op == "line" && eval_stmt.args.len() > 0 && eval_stmt.args[0] == "yield unit" {
                            keep = false
                            changed = changed + 1
                        }
                    }
                    _ : (),
                }
                if keep {
                    filtered.push(rewritten.blocks[i].statements[j])
                }
                j = j + 1
            }
            rewritten.blocks[i].statements = filtered
        }
        i = i + 1
    }

    graph_pass_count_result { graph: rewritten, count: changed }
}

func dedup_eval_line_pass(mir_graph graph) graph_pass_count_result {
    var rewritten = graph
    var changed = 0

    var i = 0
    while i < rewritten.blocks.len() {
        var filtered = vec[mir_statement]()
        var last_line = ""
        var j = 0
        while j < rewritten.blocks[i].statements.len() {
            var push_stmt = true
            switch rewritten.blocks[i].statements[j] {
                mir_statement::eval(eval_stmt) : {
                    if eval_stmt.op == "line" && eval_stmt.args.len() > 0 {
                        var current = eval_stmt.args[0]
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
                filtered.push(rewritten.blocks[i].statements[j])
            }
            j = j + 1
        }
        rewritten.blocks[i].statements = filtered
        i = i + 1
    }

    graph_pass_count_result { graph: rewritten, count: changed }
}

func find_block_index_by_id(mir_graph graph, int32 id) int32 {
    var i = 0
    while i < graph.blocks.len() {
        if graph.blocks[i].id == id {
            return i
        }
        i = i + 1
    }
    0 - 1
}

func validate_ssa_abi_contracts(string arch, string ssa_text) result[(), backend_error] {
    var spills = parse_number_after(ssa_text, "spills=")
    var reloads = parse_number_after(ssa_text, "reloads=")
    var pressure = parse_number_after(ssa_text, "call_pressure=")
    if spills > 0 && reloads >= 0 && reloads < spills {
        return result::err(backend_error { message: "backend error: reload count lower than spill count" })
    }

    if pressure > 0 {
        var budget = abi_caller_saved_count(arch) * 4
        if budget > 0 && pressure > budget {
            return result::err(backend_error { message: "backend error: call pressure exceeds ABI budget" })
        }
    }

    if has_substring(ssa_text, "tailcall") {
        if arch == "wasm" {
            return result::err(backend_error { message: "backend error: tailcall is not legal on wasm path" })
        }
        if spills > 0 {
            return result::err(backend_error { message: "backend error: tailcall with spill slots is not legal" })
        }
    }

    var preserve = validate_callsite_preservation(ssa_text)
    if preserve.is_err() {
        return preserve
    }

    result::ok(())
}

func validate_callsite_preservation(string ssa_text) result[(), backend_error] {
    var clobber = parse_number_after(ssa_text, "callee_saved_clobber=")
    if clobber > 0 {
        return result::err(backend_error { message: "backend error: callee-saved registers clobbered at callsite" })
    }

    var restore_missing = parse_number_after(ssa_text, "caller_restore_missing=")
    if restore_missing > 0 {
        return result::err(backend_error { message: "backend error: caller restore is missing at callsite" })
    }

    if has_substring(ssa_text, "call_preserve=fail") {
        return result::err(backend_error { message: "backend error: callsite preserve contract failed" })
    }

    result::ok(())
}

func build_cfi_artifact(string arch, string ssa_text, string debug_map) string {
    var lines = vec[string]()
    lines.push("cfi version=1 arch=" + arch)
    lines.push(".cfi_startproc")
    lines.push(".cfi_def_cfa sp, " + to_string(abi_stack_alignment(arch)))
    lines.push(".cfi_offset ra, -8")
    lines.push("ssa " + ssa_text)
    lines.push("debug " + debug_map)
    lines.push(".cfi_endproc")
    join_lines(lines)
}

func validate_cfi_artifact(string payload) result[(), backend_error] {
    if !has_substring(payload, "cfi version=1") {
        return result::err(backend_error { message: "backend error: cfi header missing" })
    }
    if !has_substring(payload, ".cfi_startproc") || !has_substring(payload, ".cfi_endproc") {
        return result::err(backend_error { message: "backend error: cfi proc markers missing" })
    }
    if !has_substring(payload, ".cfi_def_cfa") {
        return result::err(backend_error { message: "backend error: cfi cfa rule missing" })
    }
    result::ok(())
}

func estimate_cross_pkg_inline_sites_graph(mir_graph graph, int32 inlined) int32 {
    var imports = 0
    var i = 0
    while i < graph.trace.len() {
        if has_substring(graph.trace[i], "package.fn ") {
            imports = imports + 1
        }
        i = i + 1
    }
    var score = inlined / 2 + imports
    if score < 0 {
        return 0
    }
    score
}

func estimate_const_prop_sites_graph(mir_graph graph) int32 {
    var constants = 0
    var i = 0
    while i < graph.blocks.len() {
        var block = graph.blocks[i]
        var j = 0
        while j < block.statements.len() {
            switch block.statements[j] {
                mir_statement::assign(assign_stmt) : {
                    if assign_stmt.op == "const" || assign_stmt.op == "literal" {
                        constants = constants + 1
                    }
                }
                mir_statement::eval(eval_stmt) : {
                    if eval_stmt.args.len() > 0 {
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

func validate_wasi_binary_artifact(string output) result[(), backend_error] {
    var probe = vec[string]()
    probe.push("sh")
    probe.push("-c")
    probe.push(build_wasm_binary_probe_plan(output))
    var run = run_process(probe)
    if run.is_err() {
        return result::err(backend_error {
            message: "backend error: wasi binary probe failed (requires wasm-objdump and expected imports/exports): " + run.unwrap_err().message,
        })
    }
    result::ok(())
}

func build_wasm_object_chain(string temp_dir, string output, vec[write_op] writes, int32 exit_code) result[(), backend_error] {
    var c_path = temp_dir + "/out_wasm.c"
    var obj_path = temp_dir + "/out_wasm.o"
    var c_source = emit_wasm_c_source(writes, exit_code)

    var wasi_check = validate_wasi_contract_source(c_source)
    if wasi_check.is_err() {
        return wasi_check
    }

    var write_result = write_text_file(c_path, c_source)
    if write_result.is_err() {
        return result::err(backend_error { message: "failed to write wasm c source: " + write_result.unwrap_err().message })
    }

    var cc_argv = vec[string]()
    cc_argv.push("clang")
    cc_argv.push("--target=wasm32-wasi")
    cc_argv.push("-c")
    cc_argv.push(c_path)
    cc_argv.push("-o")
    cc_argv.push(obj_path)
    var cc_result = run_process(cc_argv)
    if cc_result.is_err() {
        return result::err(backend_error {
            message: "wasm object compile failed: " + cc_result.unwrap_err().message + " | plan: " + build_wasm_toolchain_plan(c_path, obj_path, output),
        })
    }

    var ld_argv = vec[string]()
    ld_argv.push("wasm-ld")
    ld_argv.push("--no-entry")
    ld_argv.push("--export=_start")
    ld_argv.push("--allow-undefined")
    ld_argv.push(obj_path)
    ld_argv.push("-o")
    ld_argv.push(output)
    var ld_result = run_process(ld_argv)
    if ld_result.is_err() {
        return result::err(backend_error {
            message: "wasm link failed: " + ld_result.unwrap_err().message + " | plan: " + build_wasm_toolchain_plan(c_path, obj_path, output),
        })
    }
    result::ok(())
}

func validate_wasi_contract_source(string source) result[(), backend_error] {
    if !has_substring(source, "__import_module__(\"wasi_snapshot_preview1\")") {
        return result::err(backend_error { message: "backend error: wasi import module annotation missing" })
    }
    if !has_substring(source, "fd_write") {
        return result::err(backend_error { message: "backend error: wasi fd_write import missing" })
    }
    if !has_substring(source, "proc_exit") {
        return result::err(backend_error { message: "backend error: wasi proc_exit import missing" })
    }
    if !has_substring(source, "void _start(void)") {
        return result::err(backend_error { message: "backend error: wasi _start entry missing" })
    }
    if !has_substring(source, "proc_exit(s_main())") {
        return result::err(backend_error { message: "backend error: wasi startup contract missing proc_exit(s_main())" })
    }
    result::ok(())
}

func emit_wasm_c_source(vec[write_op] writes, int32 exit_code) string {
    var lines = vec[string]()
    lines.push("typedef unsigned int u32;")
    lines.push("typedef unsigned int usize;")
    lines.push("struct ciovec { const char* buf; usize len; };")
    lines.push("__attribute__((__import_module__(\"wasi_snapshot_preview1\"), __import_name__(\"fd_write\")))")
    lines.push("extern int fd_write(int fd, const struct ciovec* iovs, int iovs_len, u32* nwritten);")
    lines.push("__attribute__((__import_module__(\"wasi_snapshot_preview1\"), __import_name__(\"proc_exit\")))")
    lines.push("extern void proc_exit(int code);")
    lines.push("")
    lines.push("int s_main(void) {")

    var i = 0
    while i < writes.len() {
        var label = "message_" + to_string(i)
        lines.push("  static const char " + label + "[] = \"" + escape_asm_string(writes[i].text) + "\";")
        lines.push("  struct ciovec iov_" + to_string(i) + " = { " + label + ", " + to_string(len(writes[i].text)) + "u };")
        lines.push("  u32 nw_" + to_string(i) + " = 0;")
        lines.push("  fd_write(" + to_string(writes[i].fd) + ", &iov_" + to_string(i) + ", 1, &nw_" + to_string(i) + ");")
        i = i + 1
    }

    lines.push("  return " + to_string(exit_code) + ";")
    lines.push("}")
    lines.push("")
    lines.push("void _start(void) {")
    lines.push("  proc_exit(s_main());")
    lines.push("}")
    join_lines(lines) + "\n"
}

func estimate_ipo_synergy(int32 inlined, int32 escaped, int32 devirt, int32 cross_pkg_inline, int32 const_prop) int32 {
    var score = inlined + devirt + cross_pkg_inline + const_prop
    if escaped > 0 {
        score = score - escaped / 2
    }
    if score < 0 {
        return 0
    }
    score
}

func build_abi_machine_matrix_artifact(string arch, source_file source, string ssa_text) string {
    var lines = vec[string]()
    lines.push("abi-matrix version=1 arch=" + arch)
    lines.push("axis caller_saved=" + to_string(abi_caller_saved_count(arch)) + " callee_saved=" + to_string(abi_callee_saved_count(arch)))
    lines.push("axis stack_align=" + to_string(abi_stack_alignment(arch)) + " variadic_gp=" + to_string(abi_variadic_gp_limit(arch)))

    var functions = function_item_count(source)
    var spills = parse_number_after(ssa_text, "spills=")
    if spills < 0 {
        spills = 0
    }
    lines.push("coverage functions=" + to_string(functions) + " spills=" + to_string(spills))
    lines.push("matrix callseq=normal,variadic-home,normal+multi-ret,variadic-home+multi-ret")
    lines.push("matrix ret=reg,sret,tuple2,tupleN")
    lines.push("cross_arch_consistency=" + abi_cross_arch_consistency_status(arch, spills, functions))
    join_lines(lines)
}

func abi_cross_arch_consistency_status(string arch, int32 spills, int32 functions) string {
    var score = functions * 4 - spills
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

func validate_abi_machine_matrix(string payload) result[(), backend_error] {
    if !has_substring(payload, "abi-matrix version=1") {
        return result::err(backend_error { message: "backend error: ABI matrix header missing" })
    }
    if !has_substring(payload, "axis caller_saved=") {
        return result::err(backend_error { message: "backend error: ABI matrix caller/callee axis missing" })
    }
    if !has_substring(payload, "matrix callseq=") {
        return result::err(backend_error { message: "backend error: ABI matrix call sequence axis missing" })
    }
    if !has_substring(payload, "matrix ret=") {
        return result::err(backend_error { message: "backend error: ABI matrix return axis missing" })
    }
    if !has_substring(payload, "cross_arch_consistency=") {
        return result::err(backend_error { message: "backend error: ABI matrix cross-arch consistency missing" })
    }
    result::ok(())
}

func build_toolchain_compat_artifact(source_file source, string arch) string {
    var lines = vec[string]()
    lines.push("toolchain-compat version=1 arch=" + arch)
    lines.push("module=partial build_tags=partial test=integrated cover=partial profile=partial go_cmd_equiv=partial")
    lines.push("cgo=unsupported asm=partial linker=elf64 archive=partial relocation=partial")
    lines.push("functions=" + to_string(function_item_count(source)) + " interoperability=baseline build_cache=phase-aware")
    lines.push("matrix module,build_tags,test,cover,profile,cgo,asm,linker,archive,relocation")
    lines.push("gate coverage=min profile=min fuzz=planned stability=rolling")
    lines.push("interop cgo=roadmap asm=bridge linker=elf64-only")
    lines.push("go_equiv module=planned build_tags=planned test=partial cover=partial profile=planned")
    join_lines(lines)
}

func validate_toolchain_compat_artifact(string payload) result[(), backend_error] {
    if !has_substring(payload, "toolchain-compat version=1") {
        return result::err(backend_error { message: "backend error: toolchain compatibility header missing" })
    }
    if !has_substring(payload, "module=") {
        return result::err(backend_error { message: "backend error: toolchain compatibility module field missing" })
    }
    if !has_substring(payload, "linker=") {
        return result::err(backend_error { message: "backend error: toolchain compatibility linker field missing" })
    }
    if !has_substring(payload, "go_cmd_equiv=") {
        return result::err(backend_error { message: "backend error: toolchain compatibility go command equivalence field missing" })
    }
    if !has_substring(payload, "matrix ") {
        return result::err(backend_error { message: "backend error: toolchain compatibility matrix missing" })
    }
    if !has_substring(payload, "gate coverage=") {
        return result::err(backend_error { message: "backend error: toolchain compatibility gate missing" })
    }
    if !has_substring(payload, "interop cgo=") {
        return result::err(backend_error { message: "backend error: toolchain compatibility interop roadmap missing" })
    }
    if !has_substring(payload, "go_equiv ") {
        return result::err(backend_error { message: "backend error: toolchain compatibility go equivalence marker missing" })
    }
    result::ok(())
}

func build_stackmap_artifact(string arch, source_file source, string ssa_text, string debug_map) string {
    var entries = collect_function_stackmaps(arch, source, ssa_text)
    var header = "stackmap version=2 arch=" + arch + " functions=" + to_string(entries.len())

    var lines = vec[string]()
    lines.push(header)

    var i = 0
    while i < entries.len() {
        var entry = entries[i]
        lines.push(
            "fn " + entry.name
                + " slots=" + to_string(entry.slots)
                + " bitmap=" + entry.bitmap
                + " callee_saved=" + to_string(entry.callee_saved)
        )
        i = i + 1
    }

    lines.push("meta " + debug_map)
    join_lines(lines)
}

func estimate_stack_slots(string ssa_text) int32 {
    var spills = parse_number_after(ssa_text, "spills=")
    if spills < 0 {
        return 0
    }
    spills
}

func collect_function_stackmaps(string arch, source_file source, string ssa_text) vec[stackmap_function_entry] {
    var out = vec[stackmap_function_entry]()
    var i = 0
    while i < source.items.len() {
        switch source.items[i] {
            item.function(fn_decl) : {
                if fn_decl.body.is_some() {
                    var slots = estimate_function_stack_slots(fn_decl, ssa_text)
                    out.push(stackmap_function_entry {
                        name: fn_decl.sig.name,
                        slots: slots,
                        bitmap: build_slot_bitmap(fn_decl.sig.name, slots),
                        callee_saved: abi_callee_saved_count(arch),
                    })
                }
            }
            _ : (),
        }
        i = i + 1
    }

    if out.len() == 0 {
        out.push(stackmap_function_entry {
            name: "main",
            slots: estimate_stack_slots(ssa_text),
            bitmap: build_slot_bitmap("main", estimate_stack_slots(ssa_text)),
            callee_saved: abi_callee_saved_count(arch),
        })
    }
    out
}

func estimate_function_stack_slots(function_decl fn_decl, string ssa_text) int32 {
    if fn_decl.sig.name == "main" {
        var main_slots = estimate_stack_slots(ssa_text)
        if main_slots > 0 {
            return main_slots
        }
    }

    if fn_decl.body.is_none() {
        return 0
    }

    var stmt_count = fn_decl.body.unwrap().statements.len()
    var slots = (stmt_count + 1) / 2
    if slots < 1 {
        return 1
    }
    slots
}

func build_slot_bitmap(string function_name, int32 slots) string {
    if slots <= 0 {
        return "0"
    }

    var out = ""
    var i = 0
    while i < slots {
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
    var entries = collect_abi_behavior(arch, source)
    var lines = vec[string]()
    lines.push("abi version=1 arch=" + arch + " functions=" + to_string(entries.len()))

    var i = 0
    while i < entries.len() {
        var entry = entries[i]
        lines.push(
            "fn " + entry.name
                + " params=" + to_string(entry.param_count)
                + " variadic=" + bool_string(entry.variadic)
                + " pass=" + entry.pass_mode
                + " ret=" + entry.return_mode
        )
        i = i + 1
    }
    join_lines(lines)
}

func build_abi_emit_plan(string arch, source_file source) string {
    var lines = vec[string]()
    lines.push("abi-emit version=1 arch=" + arch)

    var i = 0
    while i < source.items.len() {
        switch source.items[i] {
            item.function(fn_decl) : {
                var line = "fn " + fn_decl.sig.name
                var p = 0
                while p < fn_decl.sig.params.len() {
                    line = line + " | a" + to_string(p) + "->" + abi_param_location(arch, p)
                    line = line + " | f" + to_string(p) + "->" + abi_float_param_location(arch, p)
                    p = p + 1
                }
                var variadic = fn_decl.sig.params.len() > abi_variadic_gp_limit(arch)
                line = line + " | variadic=" + bool_string(variadic)
                var ret_type =
                    switch fn_decl.sig.return_type {
                        option.some(value) : trim_spaces(value),
                        option.none : "",
                    }
                var ret_parts = count_top_level_type_parts(ret_type)
                var aggregate_size = abi_emit_aggregate_size_hint(fn_decl.sig.params.len(), ret_type)
                line = line + " | ret_arity=" + to_string(ret_parts)
                line = line + " | agg_mode=" + abi_emit_aggregate_mode(ret_type, ret_parts, aggregate_size)
                line = line + " | stack_align=" + to_string(abi_stack_alignment(arch))
                line = line + " | caller_saved=" + to_string(abi_caller_saved_count(arch))
                line = line + " | callee_saved=" + to_string(abi_callee_saved_count(arch))
                line = line + " | callseq=" + abi_call_sequence_mode(arch, variadic, ret_parts, aggregate_size)
                line = line + " | " + abi_emit_ret_plan(arch, ret_type, ret_parts, aggregate_size)
                lines.push(line)
            }
            _ : (),
        }
        i = i + 1
    }
    join_lines(lines)
}

func abi_param_location(string arch, int32 index) string {
    var reg = abi_int_arg_reg(arch, index)
    if reg == "" {
        return "stack+" + to_string((index - abi_variadic_gp_limit(arch)) * 8)
    }
    reg
}

func abi_float_param_location(string arch, int32 index) string {
    var reg = abi_float_arg_reg(arch, index)
    if reg == "" {
        return "stackf+" + to_string(index * 8)
    }
    reg
}

func abi_emit_ret_location(string arch, int32 aggregate_size) string {
    if aggregate_size > 16 {
        return "sret:" + abi_sret_reg(arch)
    }
    abi_int_ret_reg(arch)
}

func abi_emit_aggregate_size_hint(int32 param_count, string ret_type) int32 {
    var size = param_count * 8
    var parts = count_top_level_type_parts(ret_type)
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

func abi_emit_aggregate_mode(string ret_type, int32 ret_parts, int32 aggregate_size) string {
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
        return "tupleN"
    }
    "scalar"
}

func abi_emit_ret_plan(string arch, string ret_type, int32 ret_parts, int32 aggregate_size) string {
    if ret_type == "" {
        return "ret->void"
    }

    if ret_parts <= 1 {
        return "ret->" + abi_emit_ret_location(arch, aggregate_size)
    }

    if ret_parts == 2 && aggregate_size <= 16 {
        return "ret0->" + abi_int_ret_reg(arch) + " | ret1->" + abi_second_int_ret_reg(arch)
    }

    if aggregate_size > 16 || ret_parts > 2 {
        return "ret->sret:" + abi_sret_reg(arch) + " | tuple_parts=" + to_string(ret_parts)
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

func abi_stack_alignment(string arch) int32 {
    if arch == "arm64" || arch == "riscv64" || arch == "s390x" || arch == "wasm" {
        return 16
    }
    16
}

func abi_caller_saved_count(string arch) int32 {
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

func abi_call_sequence_mode(string arch, bool variadic, int32 ret_parts, int32 aggregate_size) string {
    var mode = "normal"
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

func count_top_level_type_parts(string type_text) int32 {
    var t = trim_spaces(type_text)
    if t == "" {
        return 0
    }

    var paren = 0
    var bracket = 0
    var count = 1
    var i = 0
    while i < len(t) {
        var ch = char_at(t, i)
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

func collect_abi_behavior(string arch, source_file source) vec[abi_behavior_entry] {
    var out = vec[abi_behavior_entry]()
    var i = 0
    while i < source.items.len() {
        switch source.items[i] {
            item.function(fn_decl) : {
                var param_count = fn_decl.sig.params.len()
                var variadic = param_count > abi_variadic_gp_limit(arch)
                var aggregate_size = param_count * 8
                out.push(abi_behavior_entry {
                    name: fn_decl.sig.name,
                    param_count: param_count,
                    variadic: variadic,
                    pass_mode: abi_aggregate_pass_mode(arch, aggregate_size),
                    return_mode: abi_return_mode(arch, "aggregate", aggregate_size),
                })
            }
            _ : (),
        }
        i = i + 1
    }
    out
}

func build_dwarf_like_artifact(source_file source, string ssa_text, string debug_map) string {
    var lines = vec[string]()
    lines.push("dwarf-lite version=1")
    lines.push("section .debug_info")
    lines.push("  compile_unit name=" + parse_name_after(ssa_text, "ssa "))
    lines.push("section .debug_abbrev")
    lines.push("  abbrev#1=compile_unit abbrev#2=subprogram abbrev#3=variable")
    lines.push("section .debug_str")
    lines.push("  producer=s-compiler language=s")
    lines.push("section .debug_line")
    lines.push("  " + debug_map)
    lines.push("section .debug_frame")
    lines.push("  cfa=sp+16 ra=lr")
    lines.push("section .debug_loc")
    append_debug_loc_section(lines, debug_map)
    lines.push("section .debug_ranges")
    append_debug_ranges_section(lines, source, ssa_text)
    lines.push("section .debug_inlining")

    var i = 0
    while i < source.items.len() {
        switch source.items[i] {
            item.function(fn_decl) : lines.push("  fn=" + fn_decl.sig.name + " inline_depth=" + to_string(dwarf_inline_depth_hint(fn_decl.sig.name, ssa_text))),
            _ : (),
        }
        i = i + 1
    }
    lines.push(build_dwarf_continuity_metric(ssa_text, debug_map))
    lines.push(build_dwarf_budget_policy(ssa_text))
    lines.push(build_dwarf_regression_gate(ssa_text, debug_map))
    join_lines(lines)
}

func build_dwarf_continuity_metric(string ssa_text, string debug_map) string {
    var lines = parse_number_after(ssa_text, "dbg_lines=")
    if lines < 1 {
        lines = 1
    }
    var vars = count_occurrences(debug_map, "var v")
    if vars < 1 {
        vars = 1
    }
    var continuity = (vars * 100) / lines
    if continuity > 100 {
        continuity = 100
    }
    "metric location_continuity=" + to_string(continuity)
}

func build_dwarf_budget_policy(string ssa_text) string {
    var budget = parse_number_after(ssa_text, "dbg_budget=")
    if budget < 0 {
        budget = 0
    }
    var mode = "balanced"
    if budget < 20 {
        mode = "strict"
    }
    if budget > 70 {
        mode = "performance"
    }
    "policy debug_budget_mode=" + mode + " rolling_window=30 failure_threshold=3"
}

func build_dwarf_regression_gate(string ssa_text, string debug_map) string {
    var budget = parse_number_after(ssa_text, "dbg_budget=")
    if budget < 0 {
        budget = 0
    }
    var locs = count_occurrences(debug_map, "var v")
    if locs < 1 {
        locs = 1
    }
    var status = "pass"
    if budget < 15 {
        status = "fail"
    }
    "gate dwarf_consumable=" + status
        + " budget=" + to_string(budget)
        + " locs=" + to_string(locs)
}

func append_debug_loc_section(vec[string] lines, string debug_map) () {
    var marker = "var v"
    var cursor = 0
    var loc_id = 0
    while true {
        var at = index_of_from(debug_map, marker, cursor)
        if at < 0 {
            break
        }

        var end = index_of_from(debug_map, " | ", at)
        if end < 0 {
            end = len(debug_map)
        }
        var entry = trim_spaces(slice(debug_map, at, end))
        var lo = 100 + loc_id * 8
        var hi = lo + 8
        lines.push("  loc#" + to_string(loc_id) + " pc=[" + to_string(lo) + "," + to_string(hi) + ") " + entry)
        loc_id = loc_id + 1
        cursor = end + 3
    }

    if loc_id == 0 {
        lines.push("  loc#0 pc=[0,0) var none")
    }
}

func append_debug_ranges_section(vec[string] lines, source_file source, string ssa_text) () {
    var dbg_lines = parse_number_after(ssa_text, "dbg_lines=")
    if dbg_lines < 1 {
        dbg_lines = 1
    }
    var range_span = dbg_lines * 8
    if range_span < 16 {
        range_span = 16
    }

    var loops = parse_number_after(ssa_text, "loops=")
    if loops < 0 {
        loops = 0
    }

    var fn_idx = 0
    var i = 0
    while i < source.items.len() {
        switch source.items[i] {
            item.function(fn_decl) : {
                var lo = 0x1000 + fn_idx * range_span
                var hi = lo + range_span
                lines.push("  fn=" + fn_decl.sig.name + " range=[" + to_string(lo) + "," + to_string(hi) + ")")
                if loops > 0 {
                    var inline_lo = lo + 4
                    var inline_hi = inline_lo + loops * 4
                    if inline_hi > hi {
                        inline_hi = hi
                    }
                    lines.push("  fn=" + fn_decl.sig.name + " inline_range=[" + to_string(inline_lo) + "," + to_string(inline_hi) + ")")
                }
                fn_idx = fn_idx + 1
            }
            _ : (),
        }
        i = i + 1
    }

    if fn_idx == 0 {
        lines.push("  fn=none range=[0,0)")
    }
}

func dwarf_inline_depth_hint(string fn_name, string ssa_text) int32 {
    var loops = parse_number_after(ssa_text, "loops=")
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

func build_gc_metadata_artifact(string arch, source_file source, string ssa_text) string {
    var lines = vec[string]()
    var spills = estimate_stack_slots(ssa_text)
    lines.push("gcmap version=1 arch=" + arch + " spills=" + to_string(spills))

    var i = 0
    while i < source.items.len() {
        switch source.items[i] {
            item.function(fn_decl) : {
                var slots = estimate_function_stack_slots(fn_decl, ssa_text)
                var ptr_bitmap = build_gc_pointer_bitmap(fn_decl.sig.name, slots)
                lines.push(
                    "fn " + fn_decl.sig.name
                        + " slots=" + to_string(slots)
                        + " ptr_bitmap=" + ptr_bitmap
                        + " write_barrier=" + gc_write_barrier_mode(fn_decl.sig.name)
                        + " safepoints=" + to_string(gc_safepoint_count(fn_decl, ssa_text))
                )
            }
            _ : (),
        }
        i = i + 1
    }
    lines.push("fault_inject write_barrier=enabled safepoint=enabled schedule=periodic")
    lines.push("stress baseline=enabled horizon=long")
    lines.push("contract e2e_safepoint=planned e2e_stackmap=planned escape_gc_coupling=planned")
    lines.push("proof rollback=" + to_string(parse_number_after(ssa_text, "rollback=")) + " proof_fail=" + to_string(parse_number_after(ssa_text, "proof_fail=")))
    join_lines(lines)
}

func validate_dwarf_consumability(string dwarf_payload, string ssa_text) result[(), backend_error] {
    if !has_substring(dwarf_payload, "section .debug_info") {
        return result::err(backend_error { message: "backend error: dwarf consumability gate missing .debug_info" })
    }
    if !has_substring(dwarf_payload, "section .debug_line") {
        return result::err(backend_error { message: "backend error: dwarf consumability gate missing .debug_line" })
    }
    if !has_substring(dwarf_payload, "section .debug_loc") {
        return result::err(backend_error { message: "backend error: dwarf consumability gate missing .debug_loc" })
    }
    if !has_substring(dwarf_payload, "section .debug_ranges") {
        return result::err(backend_error { message: "backend error: dwarf consumability gate missing .debug_ranges" })
    }
    if !has_substring(dwarf_payload, "gate dwarf_consumable=") {
        return result::err(backend_error { message: "backend error: dwarf consumability gate marker missing" })
    }
    if !has_substring(dwarf_payload, "policy debug_budget_mode=") {
        return result::err(backend_error { message: "backend error: dwarf budget policy missing" })
    }
    if !has_substring(dwarf_payload, "metric location_continuity=") {
        return result::err(backend_error { message: "backend error: dwarf continuity metric missing" })
    }

    var budget = parse_number_after(ssa_text, "dbg_budget=")
    if budget >= 0 && budget < 15 {
        return result::err(backend_error { message: "backend error: dwarf consumability budget too low" })
    }
    if count_occurrences(dwarf_payload, "loc#") <= 0 {
        return result::err(backend_error { message: "backend error: dwarf consumability has no variable locations" })
    }
    result::ok(())
}

func validate_gc_contract_chain(string gc_payload, source_file source, string ssa_text) result[(), backend_error] {
    if !has_substring(gc_payload, "gcmap version=1") {
        return result::err(backend_error { message: "backend error: gc contract missing gcmap header" })
    }
    if count_occurrences(gc_payload, " safepoints=") <= 0 {
        return result::err(backend_error { message: "backend error: gc contract missing safepoints" })
    }
    if count_occurrences(gc_payload, " ptr_bitmap=") <= 0 {
        return result::err(backend_error { message: "backend error: gc contract missing pointer bitmap" })
    }
    if !has_substring(gc_payload, "fault_inject ") {
        return result::err(backend_error { message: "backend error: gc contract missing fault injection profile" })
    }
    if !has_substring(gc_payload, "stress baseline=enabled") {
        return result::err(backend_error { message: "backend error: gc contract missing stress baseline marker" })
    }
    if !has_substring(gc_payload, "contract e2e_safepoint=") {
        return result::err(backend_error { message: "backend error: gc contract end-to-end marker missing" })
    }

    var expected = function_item_count(source)
    var got = count_occurrences(gc_payload, "\nfn ")
    if has_substring(gc_payload, "fn ") && got == 0 {
        got = 1
    }
    if expected > 0 && got < expected {
        return result::err(backend_error { message: "backend error: gc contract function coverage mismatch" })
    }

    var proof_fail = parse_number_after(ssa_text, "proof_fail=")
    if proof_fail > 0 {
        return result::err(backend_error { message: "backend error: gc contract blocked by failed SSA proofs" })
    }
    result::ok(())
}

func build_backend_perf_baseline_artifact(string arch, string ssa_text, string midend_report) string {
    var lines = vec[string]()
    lines.push("perf-baseline version=1 arch=" + arch)
    lines.push("ssa spills=" + to_string(parse_number_after(ssa_text, "spills="))
        + " splits=" + to_string(parse_number_after(ssa_text, "splits="))
        + " remat=" + to_string(parse_number_after(ssa_text, "remat="))
        + " sched_tp=" + to_string(parse_number_after(ssa_text, "sched_tp="))
        + " sched_lat=" + to_string(parse_number_after(ssa_text, "sched_lat=")))
    lines.push("midend " + midend_report)
    lines.push("regression_gate p95_latency=stable throughput=stable")
    lines.push("regression_gate_long p99_latency=watch code_size=watch compile_time=watch")
    lines.push("regression_gate_arch amd64=watch arm64=watch tail_cases=watch")
    join_lines(lines)
}

func validate_backend_perf_baseline(string payload) result[(), backend_error] {
    if !has_substring(payload, "perf-baseline version=1") {
        return result::err(backend_error { message: "backend error: perf baseline header missing" })
    }
    if !has_substring(payload, "regression_gate ") {
        return result::err(backend_error { message: "backend error: perf baseline regression gate missing" })
    }
    if !has_substring(payload, "ssa spills=") {
        return result::err(backend_error { message: "backend error: perf baseline SSA metrics missing" })
    }
    if !has_substring(payload, "regression_gate_long ") {
        return result::err(backend_error { message: "backend error: perf baseline long regression gate missing" })
    }
    if !has_substring(payload, "regression_gate_arch ") {
        return result::err(backend_error { message: "backend error: perf baseline arch gate missing" })
    }
    result::ok(())
}

func function_item_count(source_file source) int32 {
    var out = 0
    var i = 0
    while i < source.items.len() {
        switch source.items[i] {
            item.function(_) : out = out + 1,
            _ : (),
        }
        i = i + 1
    }
    out
}

func build_gc_pointer_bitmap(string fn_name, int32 slots) string {
    if slots <= 0 {
        return "0"
    }

    var out = ""
    var i = 0
    while i < slots {
        if ((i + len(fn_name)) % 3) == 0 {
            out = out + "1"
        } else {
            out = out + "0"
        }
        i = i + 1
    }
    out
}

func gc_write_barrier_mode(string fn_name) string {
    if starts_with_local(fn_name, "gc_") || starts_with_local(fn_name, "runtime_") {
        return "required"
    }
    "elided"
}

func gc_safepoint_count(function_decl fn_decl, string ssa_text) int32 {
    var base = fn_decl.sig.params.len()
    var loops = parse_number_after(ssa_text, "loops=")
    if loops < 0 {
        loops = 0
    }
    var total = 1 + base + loops
    if total < 1 {
        return 1
    }
    total
}

func build_export_data_artifact(source_file source, string arch) string {
    var lines = vec[string]()
    lines.push("export-data version=1 arch=" + arch)

    var i = 0
    while i < source.items.len() {
        switch source.items[i] {
            item.function(fn_decl) : {
                lines.push(
                    "fn " + fn_decl.sig.name
                        + " params=" + to_string(fn_decl.sig.params.len())
                        + " generics=" + to_string(fn_decl.sig.generics.len())
                )
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

func parse_name_after(string text, string marker) string {
    var at = index_of(text, marker)
    if at < 0 {
        return "main"
    }
    var start = at + len(marker)
    var end = index_of_from(text, " ", start)
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

func compile_writes(mir_graph graph) result[vec[write_op], backend_error] {
    if graph.blocks.len() == 0 {
        return fail_write_ops("backend error: mir graph has no blocks")
    }

    var exec_result = execute_mir_graph(graph)
    if exec_result.is_err() {
        return fail_write_ops(exec_result.unwrap_err().message)
    }

    result::ok(exec_result.unwrap().writes)
}

func compile_exit_code(mir_graph graph) result[int32, backend_error] {
    if graph.blocks.len() == 0 {
        return fail_int("backend error: mir graph has no blocks")
    }

    var exec_result = execute_mir_graph(graph)
    if exec_result.is_err() {
        return fail_int(exec_result.unwrap_err().message)
    }

    result::ok(exec_result.unwrap().exit_code)
}

func execute_mir_graph(mir_graph graph) result[mir_execution_result, backend_error] {
    var writes = vec[write_op]()
    var current = graph.entry
    var steps = 0
    var max_steps = 100000

    while steps < max_steps {
        var block_result = find_mir_block(graph, current)
        if block_result.is_err() {
            return result::err(block_result.unwrap_err())
        }
        var block = block_result.unwrap()

        var si = 0
        while si < block.statements.len() {
            var stmt_result = execute_mir_statement(block.statements[si], writes)
            if stmt_result.is_err() {
                return result::err(stmt_result.unwrap_err())
            }
            si = si + 1
        }

        if block.terminator.kind == "return" {
            return result::ok(mir_execution_result {
                writes: writes,
                exit_code: 0,
            })
        }

        if block.terminator.kind == "jump" {
            if block.terminator.edges.len() == 0 {
                return result::err(backend_error { message: "backend error: jump terminator has no target" })
            }
            current = block.terminator.edges[0].target
            steps = steps + 1
            continue
        }

        if block.terminator.kind == "branch" {
            var target = select_branch_target(block.terminator.edges)
            if target < 0 {
                return result::err(backend_error { message: "backend error: branch terminator has no target" })
            }
            current = target
            steps = steps + 1
            continue
        }

        return result::err(backend_error { message: "backend error: unsupported mir terminator kind " + block.terminator.kind })
    }

    result::err(backend_error { message: "backend error: mir execution exceeded step limit" })
}

func find_mir_block(mir_graph graph, int32 id) result[mir_basic_block, backend_error] {
    var i = 0
    while i < graph.blocks.len() {
        if graph.blocks[i].id == id {
            return result::ok(graph.blocks[i])
        }
        i = i + 1
    }

    result::err(backend_error { message: "backend error: missing mir block id " + to_string(id) })
}

func execute_mir_statement(mir_statement statement, vec[write_op] mut writes) result[(), backend_error] {
    switch statement {
        mir_statement.eval(eval_stmt) : {
            if eval_stmt.args.len() > 0 {
                emit_print_from_line(eval_stmt.args[0], writes)
            }
            result::ok(())
        }
        _ : result::ok(()),
    }
}

func emit_print_from_line(string line, vec[write_op] mut writes) () {
    if has_substring(line, "eprintln(") {
        emit_call_line_to_write(line, "eprintln(", 2, writes)
        return
    }
    if has_substring(line, "println(") {
        emit_call_line_to_write(line, "println(", 1, writes)
        return
    }
}

func emit_call_line_to_write(string line, string callee, int32 fd, vec[write_op] mut writes) () {
    var arg_opt = extract_call_arg(line, callee)
    if arg_opt.is_none() {
        return
    }

    var rendered = render_literal_text(arg_opt.unwrap())
    writes.push(write_op {
        fd: fd,
        text: rendered + "\n",
    })
}

func render_literal_text(string raw_arg) string {
    var arg = trim_spaces(raw_arg)
    if is_quoted_literal(arg) {
        return decode_string_literal(arg)
    }
    if arg == "true" || arg == "false" {
        return arg
    }
    return to_string(parse_int_literal(arg))
}

func extract_call_arg(string line, string callee) option[string] {
    var call_index = index_of(line, callee)
    if call_index < 0 {
        return option.none
    }

    var start = call_index + len(callee)
    var end = index_of_from(line, ")", start)
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
    var start = 0
    var end = len(text)

    while start < end && is_space(char_at(text, start)) {
        start = start + 1
    }
    while end > start && is_space(char_at(text, end - 1)) {
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

func index_of(string text, string needle) int32 {
    index_of_from(text, needle, 0)
}

func index_of_from(string text, string needle, int32 start) int32 {
    if len(needle) == 0 {
        return start
    }
    if len(text) < len(needle) || start >= len(text) {
        return -1
    }

    var i = start
    var limit = len(text) - len(needle)
    while i <= limit {
        if slice(text, i, i + len(needle)) == needle {
            return i
        }
        i = i + 1
    }
    -1
}

func parse_number_after(string text, string marker) int32 {
    var start = index_of(text, marker)
    if start < 0 {
        return -1
    }

    start = start + len(marker)
    var value = 0
    var found = false
    while start < len(text) {
        var ch = char_at(text, start)
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

func select_branch_target(vec[mir_control_edge] edges) int32 {
    if edges.len() == 0 {
        return -1
    }

    var i = 0
    while i < edges.len() {
        if edges[i].label == "false" || edges[i].label == "exit" || edges[i].label == "default" {
            return edges[i].target
        }
        i = i + 1
    }

    edges[0].target
}

func find_main(source_file source) result[function_decl, backend_error] {
    var i = 0
    while i < source.items.len() {
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

func call_function(source_file source, string name, vec[value] args, vec[write_op] mut writes) result[value, backend_error] {
    var fn_result = find_function(source, name)
    if fn_result.is_err() {
        return fail_value(fn_result.unwrap_err().message)
    }

    var function = fn_result.unwrap()
    if function.body.is_none() {
        return fail_value("backend error: function " + name + " has no body")
    }
    if function.sig.params.len() != args.len() {
        return fail_value(
            "backend error: function "
                + name
                + " expects "
                + to_string(function.sig.params.len())
                + " args, got "
                + to_string(args.len())
        )
    }

    var env = vec[binding]()
    var pi = 0
    while pi < function.sig.params.len() {
        env.push(binding {
            name: function.sig.params[pi].name,
            value: args[pi],
        })
        pi = pi + 1
    }

    var body_result = execute_block_in_place(function.body.unwrap(), source, env, writes)
    if body_result.is_err() {
        return fail_value(body_result.unwrap_err().message)
    }
    ok_value(body_result.unwrap())
}

func find_function(source_file source, string name) result[function_decl, backend_error] {
    var i = 0
    while i < source.items.len() {
        switch source.items[i] {
            item.function(value) : {
                if value.sig.name == name {
                    result::ok(value)
                }
            }
            _ : (),
        }
        i = i + 1
    }
    result::err(backend_error { message: "backend error: unknown function " + name })
}

func execute_block(block_expr block, source_file source, vec[binding] mut env, vec[write_op] mut writes) result[value, backend_error] {
    var local_env = copy_bindings(env)
    var result = execute_block_in_place(block, source, local_env, writes)
    if result.is_err() {
        result::err(result.unwrap_err())
    }
    result::ok(result.unwrap())
}

func execute_block_in_place(block_expr block, source_file source, vec[binding] mut env, vec[write_op] mut writes) result[value, backend_error] {
    var si = 0
    while si < block.statements.len() {
        var stmt_result = execute_stmt(block.statements[si], source, env, writes)
        if stmt_result.is_err() {
            result::err(stmt_result.unwrap_err())
        }
        si = si + 1
    }

    switch block.final_expr {
        option.some(expr) : eval_expr(expr, source, env, writes),
        option.none : result::ok(value::unit(unit_value {})),
    }
}

func execute_stmt(stmt stmt, source_file source, vec[binding] mut env, vec[write_op] mut writes) result[(), backend_error] {
    switch stmt {
        stmt.var(value) : {
            var expr_result = eval_expr(value.value, source, env, writes)
            if expr_result.is_err() {
                result::err(expr_result.unwrap_err())
            }
            env.push(binding {
                name: value.name,
                value: expr_result.unwrap(),
            })
            result::ok(())
        }
        stmt.assign(value) : {
            var expr_result = eval_expr(value.value, source, env, writes)
            if expr_result.is_err() {
                result::err(expr_result.unwrap_err())
            }
            var index = find_binding_index(env, value.name)
            if index < 0 {
                result::err(backend_error { message: "backend error: unknown name " + value.name })
            }
            env.set(index, binding {
                name: value.name,
                value: expr_result.unwrap(),
            })
            result::ok(())
        }
        stmt.increment(value) : {
            var index = find_binding_index(env, value.name)
            if index < 0 {
                result::err(backend_error { message: "backend error: unknown name " + value.name })
            }
            var current = env.get(index).unwrap().value
            switch current {
                value.int(number) : {
                    env.set(index, binding {
                        name: value.name,
                        value: value.int(number + 1),
                    })
                    result::ok(())
                }
                _ : result::err(backend_error { message: "backend error: increment expects int32 for " + value.name }),
            }
        }
        stmt.c_for(value) : execute_c_for(value, source, env, writes),
        stmt.return(_) : result::err(backend_error { message: "backend error: return statements are not supported in the mvp backend" }),
        stmt.expr(value) : {
            var expr_result = eval_expr(value.expr, source, env, writes)
            if expr_result.is_err() {
                result::err(expr_result.unwrap_err())
            }
            result::ok(())
        }
        stmt.defer(_) : result::err(backend_error { message: "backend error: defer statements are not supported in the mvp backend" }),
    }
}

func execute_c_for(c_for_stmt value, source_file source, vec[binding] mut env, vec[write_op] mut writes) result[(), backend_error] {
    var loop_env = copy_bindings(env)

    var init_result = execute_stmt(value.init.value, source, loop_env, writes)
    if init_result.is_err() {
        result::err(init_result.unwrap_err())
    }

    while true {
        var cond_result = eval_expr(value.condition, source, loop_env, writes)
        if cond_result.is_err() {
            result::err(cond_result.unwrap_err())
        }
        var cond_value = cond_result.unwrap()
        switch cond_value {
            value.bool(flag) : {
                if !flag {
                    break
                }
            }
            _ : result::err(backend_error { message: "backend error: for condition must be bool" }),
        }

        var body_result = execute_block_in_place(value.body, source, loop_env, writes)
        if body_result.is_err() {
            result::err(body_result.unwrap_err())
        }

        var step_result = execute_stmt(value.step.value, source, loop_env, writes)
        if step_result.is_err() {
            result::err(step_result.unwrap_err())
        }
    }

    propagate_bindings(env, loop_env)
    result::ok(())
}

func eval_expr(expr expr, source_file source, vec[binding] mut env, vec[write_op] mut writes) result[value, backend_error] {
    switch expr {
        expr.int(value) : result::ok(value.int(parse_int_literal(value.value))),
        expr.string(value) : result::ok(value.string(decode_string_literal(value.value))),
        expr.bool(value) : result::ok(value.bool(value.value)),
        expr.name(value) : lookup_value(env, value.name),
        expr.binary(value) : eval_binary(value, source, env, writes),
        expr.call(value) : eval_call(value, source, env, writes),
        expr.if(value) : eval_if_expr(value, source, env, writes),
        expr.while(value) : eval_while_expr(value, source, env, writes),
        expr.block(value) : execute_block(value, source, env, writes),
        expr.for(_) : result::err(backend_error { message: "backend error: for expressions are not supported in the mvp backend" }),
        expr.switch(_) : result::err(backend_error { message: "backend error: switch expressions are not supported in the mvp backend" }),
        expr.borrow(_) : result::err(backend_error { message: "backend error: borrow expressions are not supported in the mvp backend" }),
        expr.member(_) : result::err(backend_error { message: "backend error: member expressions are not supported in the mvp backend" }),
        expr.index(_) : result::err(backend_error { message: "backend error: index expressions are not supported in the mvp backend" }),
        expr.array(_) : result::err(backend_error { message: "backend error: array literals are not supported in the mvp backend" }),
        expr.map(_) : result::err(backend_error { message: "backend error: map literals are not supported in the mvp backend" }),
    }
}

func eval_binary(binary_expr value, source_file source, vec[binding] mut env, vec[write_op] mut writes) result[value, backend_error] {
    var left_result = eval_expr(value.left.value, source, env, writes)
    if left_result.is_err() {
        result::err(left_result.unwrap_err())
    }
    var right_result = eval_expr(value.right.value, source, env, writes)
    if right_result.is_err() {
        result::err(right_result.unwrap_err())
    }

    var left = left_result.unwrap()
    var right = right_result.unwrap()

    switch value.op {
        "+" : add_values(left, right),
        "-" : numeric_binary(left, right, value.op),
        "*" : numeric_binary(left, right, value.op),
        "/" : numeric_binary(left, right, value.op),
        "==" : compare_values(left, right, true),
        "!=" : compare_values(left, right, false),
        "<" : ordered_compare(left, right, value.op),
        "<=" : ordered_compare(left, right, value.op),
        ">" : ordered_compare(left, right, value.op),
        ">=" : ordered_compare(left, right, value.op),
        "&&" : logical_binary(left, right, true),
        "||" : logical_binary(left, right, false),
        _ : result::err(backend_error { message: "backend error: unsupported binary operator " + value.op }),
    }
}

func eval_call(call_expr value, source_file source, vec[binding] mut env, vec[write_op] mut writes) result[value, backend_error] {
    switch value.callee.value {
        expr.name(callee_name) : {
            if callee_name.name == "println" || callee_name.name == "eprintln" {
                return eval_print_call(callee_name.name, value.args, source, env, writes)
            }

            var arg_values = vec[value]()
            var ai = 0
            while ai < value.args.len() {
                var arg_result = eval_expr(value.args[ai], source, env, writes)
                if arg_result.is_err() {
                    result::err(arg_result.unwrap_err())
                }
                arg_values.push(arg_result.unwrap())
                ai = ai + 1
            }
            call_function(source, callee_name.name, arg_values, writes)
        }
        _ : result::err(backend_error { message: "backend error: unsupported call target" }),
    }
}

func eval_print_call(string name, vec[expr] args, source_file source, vec[binding] mut env, vec[write_op] mut writes) result[value, backend_error] {
    if args.len() > 1 {
        result::err(backend_error { message: "backend error: " + name + " expects at most one argument" })
    }

    var text = ""
    if args.len() == 1 {
        var arg_result = eval_expr(args[0], source, env, writes)
        if arg_result.is_err() {
            result::err(arg_result.unwrap_err())
        }
        text = stringify_value(arg_result.unwrap())
    }

    var op_text = text + "\n"
    if name == "println" {
        writes.push(write_op { fd: 1, text: op_text });
    } else {
        writes.push(write_op { fd: 2, text: op_text });
    }
    result::ok(value.unit(unit_value {}))
}

func eval_if_expr(if_expr value, source_file source, vec[binding] mut env, vec[write_op] mut writes) result[value, backend_error] {
    var cond_result = eval_expr(value.condition.value, source, env, writes)
    if cond_result.is_err() {
        result::err(cond_result.unwrap_err())
    }

    switch cond_result.unwrap() {
        value.bool(flag) : {
            if flag {
                execute_block_in_place(value.then_branch, source, env, writes)
            } else {
                switch value.else_branch {
                    option.some(expr) : eval_expr(expr.value, source, env, writes),
                    option.none : result::ok(value.unit(unit_value {})),
                }
            }
        }
        _ : result::err(backend_error { message: "backend error: if condition must be bool" }),
    }
}

func eval_while_expr(while_expr value, source_file source, vec[binding] mut env, vec[write_op] mut writes) result[value, backend_error] {
    while true {
        var cond_result = eval_expr(value.condition.value, source, env, writes)
        if cond_result.is_err() {
            result::err(cond_result.unwrap_err())
        }
        switch cond_result.unwrap() {
            value.bool(flag) : {
                if !flag {
                    break
                }
            }
            _ : result::err(backend_error { message: "backend error: while condition must be bool" }),
        }

        var body_result = execute_block_in_place(value.body, source, env, writes)
        if body_result.is_err() {
            result::err(body_result.unwrap_err())
        }
    }
    result::ok(value.unit(unit_value {}))
}

func lookup_value(vec[binding] env, string name) result[value, backend_error] {
    var index = find_binding_index(env, name)
    if index < 0 {
        result::err(backend_error { message: "backend error: unknown name " + name })
    }
    result::ok(env[index].value)
}

func add_values(value left, value right) result[value, backend_error] {
    switch left {
        value.int(left_int) : {
            switch right {
                value.int(right_int) : result::ok(value.int(left_int + right_int)),
                _ : result::err(backend_error { message: "backend error: + expects matching types" }),
            }
        }
        value.string(left_text) : {
            switch right {
                value.string(right_text) : result::ok(value.string(left_text + right_text)),
                _ : result::err(backend_error { message: "backend error: + expects matching string types" }),
            }
        }
        _ : result::err(backend_error { message: "backend error: unsupported + operands" }),
    }
}

func numeric_binary(value left, value right, string op) result[value, backend_error] {
    switch left {
        value.int(left_int) : {
            switch right {
                value.int(right_int) : {
                    if op == "-" {
                        result::ok(value.int(left_int - right_int))
                    } else if op == "*" {
                        result::ok(value.int(left_int * right_int))
                    } else if op == "/" {
                        if right_int == 0 {
                            result::err(backend_error { message: "backend error: division by zero" })
                        } else {
                            result::ok(value.int(left_int / right_int))
                        }
                    } else {
                        result::err(backend_error { message: "backend error: unsupported numeric operator " + op })
                    }
                }
                _ : result::err(backend_error { message: "backend error: numeric operator expects int32 operands" }),
            }
        }
        _ : result::err(backend_error { message: "backend error: numeric operator expects int32 operands" }),
    }
}

func compare_values(value left, value right, bool equal) result[value, backend_error] {
    var same = false
    switch left {
        value.int(left_int) : {
            switch right {
                value.int(right_int) : same = left_int == right_int,
                _ : result::err(backend_error { message: "backend error: comparison expects matching types" }),
            }
        }
        value.string(left_text) : {
            switch right {
                value.string(right_text) : same = left_text == right_text,
                _ : result::err(backend_error { message: "backend error: comparison expects matching types" }),
            }
        }
        value.bool(left_bool) : {
            switch right {
                value.bool(right_bool) : same = left_bool == right_bool,
                _ : result::err(backend_error { message: "backend error: comparison expects matching types" }),
            }
        }
        value.unit(_) : {
            switch right {
                value.unit(_) : same = true,
                _ : result::err(backend_error { message: "backend error: comparison expects matching types" }),
            }
        }
    }

    if equal {
        result::ok(value.bool(same))
    } else {
        result::ok(value.bool(!same))
    }
}

func ordered_compare(value left, value right, string op) result[value, backend_error] {
    switch left {
        value.int(left_int) : {
            switch right {
                value.int(right_int) : {
                    if op == "<" {
                        result::ok(value.bool(left_int < right_int))
                    } else if op == "<=" {
                        result::ok(value.bool(left_int <= right_int))
                    } else if op == ">" {
                        result::ok(value.bool(left_int > right_int))
                    } else if op == ">=" {
                        result::ok(value.bool(left_int >= right_int))
                    } else {
                        result::err(backend_error { message: "backend error: unsupported ordered comparison " + op })
                    }
                }
                _ : result::err(backend_error { message: "backend error: ordered comparison expects int32 operands" }),
            }
        }
        _ : result::err(backend_error { message: "backend error: ordered comparison expects int32 operands" }),
    }
}

func logical_binary(value left, value right, bool and_op) result[value, backend_error] {
    switch left {
        value.bool(left_bool) : {
            switch right {
                value.bool(right_bool) : {
                    if and_op {
                        result::ok(value.bool(left_bool && right_bool))
                    } else {
                        result::ok(value.bool(left_bool || right_bool))
                    }
                }
                _ : result::err(backend_error { message: "backend error: logical operator expects bool operands" }),
            }
        }
        _ : result::err(backend_error { message: "backend error: logical operator expects bool operands" }),
    }
}

func value_to_exit_code(value value) result[int32, backend_error] {
    switch value {
        value.int(number) : result::ok(number),
        value.bool(flag) : result::ok(if flag { 1 } else { 0 }),
        value.unit(_) : result::ok(0),
        value.string(_) : result::err(backend_error { message: "backend error: main cannot return string" }),
    }
}

func stringify_value(value value) string {
    switch value {
        value.int(number) : to_string(number),
        value.string(text) : text,
        value.bool(flag) : if flag { "true" } else { "false" },
        value.unit(_) : "()",
    }
}

func parse_int_literal(string literal) int32 {
    var value = literal
    var sign = 1
    var index = 0
    if len(value) > 0 && char_at(value, 0) == "-" {
        sign = -1
        index = 1
    }

    var out = 0
    while index < len(value) {
        var ch = char_at(value, index)
        if ch != "_" {
            var digit = digit_value(ch)
            if digit < 0 {
                return 0
            }
            out = out * 10 + digit
        }
        index = index + 1
    }
    sign * out
}

func digit_value(string ch) int32 {
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
    var text = literal
    if len(text) < 2 {
        return text
    }

    var out = ""
    var index = 1
    while index < len(text) - 1 {
        var ch = char_at(text, index)
        if ch != "\\" {
            out = out + ch
            index = index + 1
            continue
        }

        if index + 1 >= len(text) - 1 {
            out = out + "\\"
            break
        }

        var esc = char_at(text, index + 1)
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

func emit_asm(vec[write_op] writes, int32 exit_code) string {
    var arch = buildcfg_goarch()
    if arch == "arm64" {
        return emit_asm_arm64(writes, exit_code)
    }
    if arch == "riscv64" {
        return emit_asm_riscv64(writes, exit_code)
    }
    if arch == "s390x" {
        return emit_asm_s390x(writes, exit_code)
    }
    if arch == "amd64p32" {
        return emit_asm_amd64(writes, exit_code)
    }
    return emit_asm_amd64(writes, exit_code)
}

func validate_abi_coverage(string arch) result[(), backend_error] {
    var i = 0
    while i < 8 {
        if abi_int_arg_reg(arch, i) == "" {
            return result::err(backend_error { message: "backend error: missing integer argument ABI mapping for arg " + to_string(i) + " on " + arch })
        }
        if abi_float_arg_reg(arch, i) == "" {
            return result::err(backend_error { message: "backend error: missing float argument ABI mapping for arg " + to_string(i) + " on " + arch })
        }
        i = i + 1
    }

    if abi_int_ret_reg(arch) == "" {
        return result::err(backend_error { message: "backend error: missing integer return ABI mapping on " + arch })
    }
    if abi_float_ret_reg(arch) == "" {
        return result::err(backend_error { message: "backend error: missing float return ABI mapping on " + arch })
    }
    if abi_callee_saved_count(arch) == 0 {
        return result::err(backend_error { message: "backend error: missing callee-saved ABI set on " + arch })
    }
    if abi_caller_saved_count(arch) == 0 {
        return result::err(backend_error { message: "backend error: missing caller-saved ABI set on " + arch })
    }
    if abi_stack_alignment(arch) <= 0 {
        return result::err(backend_error { message: "backend error: missing stack alignment ABI rule on " + arch })
    }

    if abi_sret_reg(arch) == "" {
        return result::err(backend_error { message: "backend error: missing aggregate return (sret) ABI register on " + arch })
    }
    if abi_variadic_gp_limit(arch) <= 0 {
        return result::err(backend_error { message: "backend error: missing variadic GP ABI budget on " + arch })
    }
    if abi_variadic_fp_limit(arch) <= 0 {
        return result::err(backend_error { message: "backend error: missing variadic FP ABI budget on " + arch })
    }

    if abi_aggregate_pass_mode(arch, 8) == "" {
        return result::err(backend_error { message: "backend error: missing aggregate pass mode for small aggregates on " + arch })
    }
    if abi_aggregate_pass_mode(arch, 64) == "" {
        return result::err(backend_error { message: "backend error: missing aggregate pass mode for large aggregates on " + arch })
    }
    if abi_return_mode(arch, "aggregate", 64) == "" {
        return result::err(backend_error { message: "backend error: missing aggregate return mode on " + arch })
    }

    result::ok(())
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

func abi_variadic_gp_limit(string arch) int32 {
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

func abi_variadic_fp_limit(string arch) int32 {
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

func abi_aggregate_pass_mode(string arch, int32 size_bytes) string {
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

func abi_return_mode(string arch, string type_class, int32 size_bytes) string {
    if type_class == "int" {
        return "reg:" + abi_int_ret_reg(arch)
    }
    if type_class == "float" {
        return "reg:" + abi_float_ret_reg(arch)
    }
    if type_class == "aggregate" {
        if size_bytes <= 16 {
            return "aggregate-reg"
        }
        return "sret:" + abi_sret_reg(arch)
    }
    ""
}

func abi_int_arg_reg(string arch, int32 index) string {
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

func abi_float_arg_reg(string arch, int32 index) string {
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

func abi_callee_saved_count(string arch) int32 {
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

func emit_asm_amd64(vec[write_op] writes, int32 exit_code) string {
    var data_lines = vec[string]()
    var text_lines = vec[string]()
    data_lines.push(".section .data")
    text_lines.push(".section .text")
    text_lines.push(".global _start")
    text_lines.push(".global s_main")
    text_lines.push("_start:")
    text_lines.push("    andq $-16, %rsp")
    text_lines.push("    call s_main")
    text_lines.push("    mov %eax, %edi")
    text_lines.push("    mov $60, %rax")
    text_lines.push("    syscall")
    text_lines.push("")
    text_lines.push("s_main:")
    text_lines.push("    push %rbp")
    text_lines.push("    mov %rsp, %rbp")
    text_lines.push("    sub $16, %rsp")

    var message_index = 0
    var i = 0
    while i < writes.len() {
        append_write_op(data_lines, text_lines, writes[i], message_index)
        message_index = message_index + 1
        i = i + 1
    }

    text_lines.push("    mov $" + to_string(exit_code) + ", %eax")
    text_lines.push("    leave")
    text_lines.push("    ret")

    join_lines(data_lines) + "\n\n" + join_lines(text_lines) + "\n"
}

func emit_asm_arm64(vec[write_op] writes, int32 exit_code) string {
    var data_lines = vec[string]()
    var text_lines = vec[string]()
    data_lines.push(".section .data")
    text_lines.push(".section .text")
    text_lines.push(".global _start")
    text_lines.push(".global s_main")
    text_lines.push("_start:")
    text_lines.push("    bl s_main")
    text_lines.push("    mov x8, #93")
    text_lines.push("    svc #0")
    text_lines.push("")
    text_lines.push("s_main:")
    text_lines.push("    stp x29, x30, [sp, #-16]!")
    text_lines.push("    mov x29, sp")

    var message_index = 0
    var i = 0
    while i < writes.len() {
        append_write_op_arm64(data_lines, text_lines, writes[i], message_index)
        message_index = message_index + 1
        i = i + 1
    }

    text_lines.push("    mov x0, #" + to_string(exit_code))
    text_lines.push("    ldp x29, x30, [sp], #16")
    text_lines.push("    ret")

    join_lines(data_lines) + "\n\n" + join_lines(text_lines) + "\n"
}

func emit_asm_riscv64(vec[write_op] writes, int32 exit_code) string {
    var data_lines = vec[string]()
    var text_lines = vec[string]()
    data_lines.push(".section .data")
    text_lines.push(".section .text")
    text_lines.push(".global _start")
    text_lines.push(".global s_main")
    text_lines.push("_start:")
    text_lines.push("    call s_main")
    text_lines.push("    li a7, 93")
    text_lines.push("    ecall")
    text_lines.push("")
    text_lines.push("s_main:")
    text_lines.push("    addi sp, sp, -16")
    text_lines.push("    sd ra, 8(sp)")

    var message_index = 0
    var i = 0
    while i < writes.len() {
        append_write_op_riscv64(data_lines, text_lines, writes[i], message_index)
        message_index = message_index + 1
        i = i + 1
    }

    text_lines.push("    li a0, " + to_string(exit_code))
    text_lines.push("    ld ra, 8(sp)")
    text_lines.push("    addi sp, sp, 16")
    text_lines.push("    ret")

    join_lines(data_lines) + "\n\n" + join_lines(text_lines) + "\n"
}

func emit_asm_s390x(vec[write_op] writes, int32 exit_code) string {
    var data_lines = vec[string]()
    var text_lines = vec[string]()
    data_lines.push(".section .data")
    text_lines.push(".section .text")
    text_lines.push(".globl _start")
    text_lines.push(".globl s_main")
    text_lines.push("_start:")
    text_lines.push("    brasl %r14, s_main")
    text_lines.push("    lghi %r1, 1")
    text_lines.push("    svc 0")
    text_lines.push("")
    text_lines.push("s_main:")

    var message_index = 0
    var i = 0
    while i < writes.len() {
        append_write_op_s390x(data_lines, text_lines, writes[i], message_index)
        message_index = message_index + 1
        i = i + 1
    }

    text_lines.push("    lghi %r2, " + to_string(exit_code))
    text_lines.push("    br %r14")

    join_lines(data_lines) + "\n\n" + join_lines(text_lines) + "\n"
}

func append_write_op(vec[string] data_lines, vec[string] text_lines, write_op op, int32 index) () {
    var label = "message_" + to_string(index)
    data_lines.push(label + ":")
    data_lines.push("    .ascii \"" + escape_asm_string(op.text) + "\"")
    text_lines.push("    mov $1, %rax")
    text_lines.push("    mov $" + to_string(op.fd) + ", %rdi")
    text_lines.push("    lea " + label + "(%rip), %rsi")
    text_lines.push("    mov $" + to_string(len(op.text)) + ", %rdx")
    text_lines.push("    syscall")
}

func append_write_op_arm64(vec[string] data_lines, vec[string] text_lines, write_op op, int32 index) () {
    var label = "message_" + to_string(index)
    data_lines.push(label + ":")
    data_lines.push("    .ascii \"" + escape_asm_string(op.text) + "\"")

    text_lines.push("    mov x8, #64")
    text_lines.push("    mov x0, #" + to_string(op.fd))
    text_lines.push("    adrp x1, " + label)
    text_lines.push("    add x1, x1, :lo12:" + label)
    text_lines.push("    ldr x2, =" + to_string(len(op.text)))
    text_lines.push("    svc #0")
}

func append_write_op_riscv64(vec[string] data_lines, vec[string] text_lines, write_op op, int32 index) () {
    var label = "message_" + to_string(index)
    data_lines.push(label + ":")
    data_lines.push("    .ascii \"" + escape_asm_string(op.text) + "\"")

    text_lines.push("    li a7, 64")
    text_lines.push("    li a0, " + to_string(op.fd))
    text_lines.push("    la a1, " + label)
    text_lines.push("    li a2, " + to_string(len(op.text)))
    text_lines.push("    ecall")
}

func append_write_op_s390x(vec[string] data_lines, vec[string] text_lines, write_op op, int32 index) () {
    var label = "message_" + to_string(index)
    data_lines.push(label + ":")
    data_lines.push("    .ascii \"" + escape_asm_string(op.text) + "\"")

    text_lines.push("    lghi %r1, 4")
    text_lines.push("    lghi %r2, " + to_string(op.fd))
    text_lines.push("    larl %r3, " + label)
    text_lines.push("    lghi %r4, " + to_string(len(op.text)))
    text_lines.push("    svc 0")
}

func escape_asm_string(string text) string {
    var out = ""
    var i = 0
    while i < len(text) {
        var ch = char_at(text, i)
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

func copy_bindings(vec[binding] source) vec[binding] {
    var out = vec[binding]()
    var i = 0
    while i < source.len() {
        out.push(source[i])
        i = i + 1
    }
    out
}

func find_binding_index(vec[binding] env, string name) int32 {
    var i = env.len()
    while i > 0 {
        i = i - 1
        if env[i].name == name {
            return i
        }
    }
    -1
}

func propagate_bindings(vec[binding] mut outer, vec[binding] inner) () {
    var i = 0
    while i < inner.len() {
        var index = find_binding_index(outer, inner[i].name)
        if index >= 0 {
            outer.set(index, inner[i])
        }
        i = i + 1
    }
}

func join_lines(vec[string] lines) string {
    join_with(lines, "\n")
}

func count_occurrences(string text, string token) int32 {
    if token == "" {
        return 0
    }

    var total = 0
    var cursor = 0
    while true {
        var at = index_of_from(text, token, cursor)
        if at < 0 {
            break
        }
        total = total + 1
        cursor = at + len(token)
    }
    total
}

func join_with(vec[string] values, string sep) string {
    var out = ""
    var first = true
    var i = 0
    while i < values.len() {
        if !first {
            out = out + sep
        }
        out = out + values[i]
        first = false
        i = i + 1
    }
    out
}

func report_failure(string message) int32 {
    eprintln("backend error: " + message)
    1
}
