package compile.internal.ssa_core

use compile.internal.mir.mir_graph
use compile.internal.mir.mir_statement
use compile.internal.mir.dump_graph
use std.prelude.char_at
use std.prelude.len
use std.prelude.slice
use std.prelude.to_string
use std.vec.vec

struct ssa_pipeline_options {
    bool enable_dce
    bool enable_coalesce
    bool enable_simplify_cfg
    int32 dominant_margin_override
}

struct ssa_program {
    string function_name
    string optimized_mir_text
    string pass_mir_trace
    string pass_delta_trace
    string pass_delta_summary
    string pass_delta_structural_summary
    string pass_delta_value_summary
    string pass_delta_hot_summary
    int32 block_count
    int32 value_count
    int32 cfg_edge_count
    int32 branch_block_count
    int32 optimized_value_count
    int32 folded_constant_count
    int32 dce_removed_count
    int32 coalesced_move_count
    int32 simplified_branch_count
    int32 gvn_rewrite_count
    int32 sccp_rewrite_count
    int32 pre_eliminated_count
    int32 cse_eliminated_count
    int32 licm_hoisted_count
    int32 bce_removed_count
    int32 phi_node_count
    int32 def_use_edge_count
    int32 alias_set_count
    int32 memory_version_count
    int32 live_in_fact_count
    int32 loop_header_count
    int32 semantic_rewrite_count
    int32 fixed_point_iterations
    int32 verification_error_count
    int32 rollback_count
    int32 proof_obligation_count
    int32 proof_failed_count
    int32 scheduled_pass_count
    int32 blocked_pass_count
    int32 dag_level_count
    int32 rerun_count
    int32 rollback_checkpoint_count
    int32 invalidation_rerun_count
    int32 replay_step_count
    int32 debug_budget_score
    int32 scheduler_priority_score
    int32 scheduler_conflict_count
    int32 replay_stability_hash
    int32 alias_precision_level
    int32 memory_ssa_chain_count
    int32 global_value_number_count
    int32 loop_proof_chain_count
    int32 spill_cost_score
    int32 split_quality_score
    int32 cross_block_gain_score
    int32 sched_throughput_score
    int32 sched_latency_balance_score
    int32 microarch_specialization_score
    int32 cost_model_score
    int32 solver_convergence_score
    int32 replay_determinism_score
    string pass_dsl
    string invalidation_policy
    string pass_topology_log
    string pass_replay_log
    string rollback_node
    int32 spill_count
    int32 spill_reload_count
    int32 call_pressure_event_count
    int32 live_range_split_count
    int32 rematerialized_value_count
    int32 regalloc_reuse_count
    int32 regalloc_max_live
    int32 debug_line_count
    vec[string] allocated_regs
    vec[string] debug_lines
    vec[string] debug_var_locations
}

struct ssa_rewrite_result {
    string rewritten_mir
    int32 rewrite_count
}

struct mir_metrics {
    int32 blocks
    int32 stmts
    int32 branches
    int32 jumps
    int32 consts
    int32 imms
    int32 literals
    int32 phi
    int32 memphi
    int32 copy
    int32 load
    int32 store
}

struct ssa_pass_stats {
    int32 folded_constant_count
    int32 dce_removed_count
    int32 coalesced_move_count
    int32 simplified_branch_count
    int32 gvn_rewrite_count
    int32 sccp_rewrite_count
    int32 pre_eliminated_count
    int32 cse_eliminated_count
    int32 licm_hoisted_count
    int32 bce_removed_count
    int32 phi_node_count
    int32 def_use_edge_count
    int32 alias_set_count
    int32 memory_version_count
    int32 live_in_fact_count
    int32 loop_header_count
    int32 fixed_point_iterations
    int32 verification_error_count
    int32 rollback_count
    int32 proof_obligation_count
    int32 proof_failed_count
    int32 scheduled_pass_count
    int32 blocked_pass_count
    int32 dag_level_count
    int32 rerun_count
    int32 rollback_checkpoint_count
    int32 invalidation_rerun_count
    int32 replay_step_count
    int32 scheduler_priority_score
    int32 scheduler_conflict_count
    int32 replay_stability_hash
    int32 cost_model_score
    int32 solver_convergence_score
    int32 replay_determinism_score
    int32 alias_precision_level
    int32 memory_ssa_chain_count
    int32 global_value_number_count
    int32 loop_proof_chain_count
    string pass_dsl
    string invalidation_policy
    string pass_topology_log
    string pass_replay_log
    string rollback_node
    int32 optimized_value_count
}

struct pass_node_result {
    int32 rewrites
    int32 blocked
    string replay_token
}

struct ssa_dataflow_model {
    int32 block_count
    int32 edge_count
    int32 value_count
    int32 branch_count
    int32 jump_count
    int32 call_count
    int32 load_count
    int32 store_count
    int32 phi_count
    int32 memphi_count
    int32 alias_set_count
    int32 def_use_edges
    int32 live_in_facts
    int32 loop_headers
}

func build_pipeline(string mir_text, string goarch) ssa_program {
    return build_pipeline_with_options(mir_text, goarch, default_options())
}

func build_pipeline_with_margin(string mir_text, string goarch, int32 dominant_margin_override) ssa_program {
    var options = default_options()
    options.dominant_margin_override = dominant_margin_override
    return build_pipeline_with_options(mir_text, goarch, options)
}

func build_pipeline_with_graph_hints(mir_graph graph, string mir_text, string goarch) ssa_program {
    var program = build_pipeline(mir_text, goarch)

    var graph_blocks = graph.blocks.len()
    var graph_values = 0
    var graph_branches = 0
    var graph_edges = 0
    var i = 0
    while i < graph.blocks.len() {
        var block = graph.blocks[i]
        graph_values = graph_values + block.statements.len()
        graph_edges = graph_edges + block.terminator.edges.len()
        if block.terminator.kind == "branch" {
            graph_branches = graph_branches + 1
        }

        var j = 0
        while j < block.statements.len() {
            switch block.statements[j] {
                mir_statement::assign(assign_stmt) : {
                    if assign_stmt.op == "phi" {
                        program.phi_node_count = program.phi_node_count + 1
                    }
                }
                _ : (),
            }
            j = j + 1
        }
        i = i + 1
    }

    if graph_blocks > 0 {
        program.block_count = graph_blocks
    }
    if graph_values > 0 {
        program.value_count = graph_values
    }
    if graph_edges > 0 {
        program.cfg_edge_count = graph_edges
    }
    if graph_branches > 0 {
        program.branch_block_count = graph_branches
    }
    if program.block_count > 0 && program.value_count > 0 {
        program.def_use_edge_count = program.value_count + program.block_count
    }

    program.debug_lines = build_debug_lines(dump_graph(graph), program.allocated_regs)
    program.debug_line_count = program.debug_lines.len()
    program
}

func build_pipeline_with_graph_hints_and_margin(mir_graph graph, string mir_text, string goarch, int32 dominant_margin_override) ssa_program {
    var program = build_pipeline_with_margin(mir_text, goarch, dominant_margin_override)

    var graph_blocks = graph.blocks.len()
    var graph_values = 0
    var graph_branches = 0
    var graph_edges = 0
    var i = 0
    while i < graph.blocks.len() {
        var block = graph.blocks[i]
        graph_values = graph_values + block.statements.len()
        graph_edges = graph_edges + block.terminator.edges.len()
        if block.terminator.kind == "branch" {
            graph_branches = graph_branches + 1
        }

        var j = 0
        while j < block.statements.len() {
            switch block.statements[j] {
                mir_statement::assign(assign_stmt) : {
                    if assign_stmt.op == "phi" {
                        program.phi_node_count = program.phi_node_count + 1
                    }
                }
                _ : ()
            }
            j = j + 1
        }

        i = i + 1
    }

    if graph_blocks > 0 {
        program.block_count = graph_blocks
    }
    if graph_values > 0 {
        program.value_count = graph_values
    }
    if graph_edges > 0 {
        program.cfg_edge_count = graph_edges
    }
    if graph_branches > 0 {
        program.branch_block_count = graph_branches
    }
    if program.block_count > 0 && program.value_count > 0 {
        program.def_use_edge_count = program.value_count + program.block_count
    }

    program.debug_lines = build_debug_lines(dump_graph(graph), program.allocated_regs)
    program.debug_line_count = program.debug_lines.len()
    program
}

func build_pipeline_with_options(string mir_text, string goarch, ssa_pipeline_options options) ssa_program {
    var rewrite = canonicalize_mir(mir_text)
    var rewritten = rewrite.rewritten_mir

    var function_name = parse_function_name(rewritten)
    var block_count = parse_int_after(rewritten, "blocks=")
    var value_count = parse_total_stmt_count(rewritten)
    if value_count == 0 {
        value_count = block_count
    }
    var model = build_dataflow_model(rewritten, block_count, value_count)
    var pass_stats = run_optimization_passes(rewritten, model, options)
    var pass_mir_trace = build_pass_mir_trace(rewritten, pass_stats, options)
    var pass_delta_trace = build_pass_delta_trace(rewritten, pass_stats, options)
    var pass_delta_summary = build_pass_delta_summary(pass_delta_trace)
    var pass_delta_structural_summary = build_pass_delta_category_summary(pass_delta_trace, true)
    var pass_delta_value_summary = build_pass_delta_category_summary(pass_delta_trace, false)
    var pass_delta_hot_summary = build_pass_delta_hot_summary(pass_delta_structural_summary, pass_delta_value_summary, options.dominant_margin_override)
    var optimized_mir = apply_pipeline_rewrites(rewritten, pass_stats, options)
    var optimized_block_count = parse_int_after(optimized_mir, "blocks=")
    if optimized_block_count <= 0 {
        optimized_block_count = block_count
    }
    var optimized_value_count = pass_stats.optimized_value_count
    var optimized_text_value_count = parse_total_stmt_count(optimized_mir)
    if optimized_text_value_count > 0 {
        optimized_value_count = optimized_text_value_count
    }
    if pass_stats.verification_error_count > 0 {
        optimized_value_count = value_count
        optimized_mir = rewritten
    }
    var allocation = linear_scan_regalloc_with_spill(optimized_mir, optimized_value_count, goarch)
    var debug_budget = compute_debug_budget(pass_stats, allocation)
    var regalloc_quality = compute_regalloc_quality(allocation, optimized_block_count)
    var sched_quality = compute_schedule_quality(pass_stats, model, goarch)
    var debug_lines = build_debug_lines(optimized_mir, allocation.allocated_regs)
    var debug_var_locations = build_var_locations(allocation.allocated_regs)

    ssa_program {
        function_name: function_name,
        optimized_mir_text: optimized_mir,
        pass_mir_trace: pass_mir_trace,
        pass_delta_trace: pass_delta_trace,
        pass_delta_summary: pass_delta_summary,
        pass_delta_structural_summary: pass_delta_structural_summary,
        pass_delta_value_summary: pass_delta_value_summary,
        pass_delta_hot_summary: pass_delta_hot_summary,
        block_count: optimized_block_count,
        value_count: value_count,
        cfg_edge_count: estimate_cfg_edges(optimized_mir),
        branch_block_count: count_token(optimized_mir, " term=branch"),
        optimized_value_count: optimized_value_count,
        folded_constant_count: pass_stats.folded_constant_count,
        dce_removed_count: pass_stats.dce_removed_count,
        coalesced_move_count: pass_stats.coalesced_move_count,
        simplified_branch_count: pass_stats.simplified_branch_count,
        gvn_rewrite_count: pass_stats.gvn_rewrite_count,
        sccp_rewrite_count: pass_stats.sccp_rewrite_count,
        pre_eliminated_count: pass_stats.pre_eliminated_count,
        cse_eliminated_count: pass_stats.cse_eliminated_count,
        licm_hoisted_count: pass_stats.licm_hoisted_count,
        bce_removed_count: pass_stats.bce_removed_count,
        phi_node_count: pass_stats.phi_node_count,
        def_use_edge_count: pass_stats.def_use_edge_count,
        alias_set_count: pass_stats.alias_set_count,
        memory_version_count: pass_stats.memory_version_count,
        live_in_fact_count: pass_stats.live_in_fact_count,
        loop_header_count: pass_stats.loop_header_count,
        semantic_rewrite_count: rewrite.rewrite_count,
        fixed_point_iterations: pass_stats.fixed_point_iterations,
        verification_error_count: pass_stats.verification_error_count,
        rollback_count: pass_stats.rollback_count,
        proof_obligation_count: pass_stats.proof_obligation_count,
        proof_failed_count: pass_stats.proof_failed_count,
        scheduled_pass_count: pass_stats.scheduled_pass_count,
        blocked_pass_count: pass_stats.blocked_pass_count,
        dag_level_count: pass_stats.dag_level_count,
        rerun_count: pass_stats.rerun_count,
        rollback_checkpoint_count: pass_stats.rollback_checkpoint_count,
        invalidation_rerun_count: pass_stats.invalidation_rerun_count,
        replay_step_count: pass_stats.replay_step_count,
        debug_budget_score: debug_budget,
        scheduler_priority_score: pass_stats.scheduler_priority_score,
        scheduler_conflict_count: pass_stats.scheduler_conflict_count,
        replay_stability_hash: pass_stats.replay_stability_hash,
        alias_precision_level: pass_stats.alias_precision_level,
        memory_ssa_chain_count: pass_stats.memory_ssa_chain_count,
        global_value_number_count: pass_stats.global_value_number_count,
        loop_proof_chain_count: pass_stats.loop_proof_chain_count,
        spill_cost_score: regalloc_quality.spill_cost_score,
        split_quality_score: regalloc_quality.split_quality_score,
        cross_block_gain_score: regalloc_quality.cross_block_gain_score,
        sched_throughput_score: sched_quality.throughput_score,
        sched_latency_balance_score: sched_quality.latency_balance_score,
        microarch_specialization_score: sched_quality.microarch_specialization_score,
        cost_model_score: pass_stats.cost_model_score,
        solver_convergence_score: pass_stats.solver_convergence_score,
        replay_determinism_score: pass_stats.replay_determinism_score,
        pass_dsl: pass_stats.pass_dsl,
        invalidation_policy: pass_stats.invalidation_policy,
        pass_topology_log: pass_stats.pass_topology_log,
        pass_replay_log: pass_stats.pass_replay_log,
        rollback_node: pass_stats.rollback_node,
        spill_count: allocation.spill_count,
        spill_reload_count: allocation.spill_reload_count,
        call_pressure_event_count: allocation.call_pressure_events,
        live_range_split_count: allocation.live_range_splits,
        rematerialized_value_count: allocation.rematerialized_values,
        regalloc_reuse_count: allocation.reuse_count,
        regalloc_max_live: allocation.max_live,
        debug_line_count: debug_lines.len(),
        allocated_regs: allocation.allocated_regs,
        debug_lines: debug_lines,
        debug_var_locations: debug_var_locations,
    }
}

func canonicalize_mir(string mir_text) ssa_rewrite_result {
    var rewritten = mir_text
    var rewrites = 0

    var r0 = replace_first_token(rewritten, " term=jump |", " term=return |")
    if r0.changed {
        rewritten = r0.text
        rewrites = rewrites + 1
    }

    var r1 = replace_first_token(rewritten, " stmts=0 term=branch", " stmts=0 term=jump")
    if r1.changed {
        rewritten = r1.text
        rewrites = rewrites + 1
    }

    ssa_rewrite_result {
        rewritten_mir: rewritten,
        rewrite_count: rewrites,
    }
}

struct replace_result {
    string text
    bool changed
}

func replace_first_token(string text, string needle, string replacement) replace_result {
    var pos = find_token(text, needle)
    if pos > text.len() {
        return replace_result {
            text: text,
            changed: false,
        }
    }

    replace_result {
        text: slice(text, 0, pos) + replacement + slice(text, pos + needle.len(), text.len()),
        changed: true,
    }
}

struct regalloc_result {
    vec[string] allocated_regs
    int32 spill_count
    int32 spill_reload_count
    int32 call_pressure_events
    int32 live_range_splits
    int32 rematerialized_values
    int32 reuse_count
    int32 max_live
}

struct regalloc_quality_result {
    int32 spill_cost_score
    int32 split_quality_score
    int32 cross_block_gain_score
}

struct schedule_quality_result {
    int32 throughput_score
    int32 latency_balance_score
    int32 microarch_specialization_score
}

func linear_scan_regalloc_with_spill(string mir_text, int32 value_count, string goarch) regalloc_result {
    var regs = register_bank(goarch)
    var call_sites = count_token(mir_text, " call=")
    var remat_sites = count_token(mir_text, " const") + count_token(mir_text, " imm") + count_token(mir_text, " literal=")
    var blocks = parse_number_after(mir_text, "blocks=")
    if blocks < 1 {
        blocks = 1
    }
    if regs.len() == 0 {
        return regalloc_result {
            allocated_regs: vec[string](),
            spill_count: value_count,
            spill_reload_count: value_count,
            call_pressure_events: call_sites,
            live_range_splits: 0,
            rematerialized_values: 0,
            reuse_count: 0,
            max_live: 0,
        }
    }

    var active_until = vec[int32]()
    var ri = 0
    while ri < regs.len() {
        active_until.push(0)
        ri = ri + 1
    }

    var out = vec[string]()
    var spills = 0
    var spill_reloads = 0
    var splits = 0
    var remat = 0
    var reuse = 0
    var max_live = 0
    var live_width = 3
    if call_sites > 0 {

        live_width = 2
    }

    var i = 0
    while i < value_count {
        var chosen = -1
        ri = 0
        while ri < regs.len() {
            if i >= active_until[ri] {
                chosen = ri
                break
            }
            ri = ri + 1
        }

        if chosen >= 0 {
            if i >= regs.len() {
                reuse = reuse + 1
            }
            var hold = choose_live_width(i, value_count, live_width, call_sites)
            active_until[chosen] = i + hold
            out.push(regs[chosen])

            var live_now = count_live_regs(active_until, i)
            if live_now > max_live {
                max_live = live_now
            }
        } else {
            var victim = pick_split_victim(active_until)
            var victim_live_until = active_until[victim]
            var remat_candidate = should_rematerialize_value(i, remat_sites, call_sites, value_count)
            var split_candidate = should_split_live_range(i, victim_live_until, value_count, call_sites, blocks)

            if remat_candidate {
                out.push("remat(v" + to_string(i) + ")")
                remat = remat + 1
            } else if split_candidate {
                active_until[victim] = i + choose_live_width(i, value_count, live_width, call_sites)
                out.push("split(v" + to_string(i) + "->" + regs[victim] + ")")
                splits = splits + 1
                spill_reloads = spill_reloads + 1
            } else {
                out.push("spill(" + to_string(i - regs.len()) + ")")
                spills = spills + 1
                spill_reloads = spill_reloads + 1
            }
        }
        i = i + 1
    }

    regalloc_result {
        allocated_regs: out,
        spill_count: spills,
        spill_reload_count: spill_reloads,
        call_pressure_events: call_sites,
        live_range_splits: splits,
        rematerialized_values: remat,
        reuse_count: reuse,
        max_live: max_live,
    }
}

func choose_live_width(int32 index, int32 value_count, int32 base_width, int32 call_sites) int32 {
    var width = base_width
    if call_sites > 0 && index > (value_count / 2) {
        width = width - 1
    }
    if width < 1 {
        return 1
    }
    width
}

func pick_split_victim(vec[int32] active_until) int32 {
    var victim = 0
    var max_until = active_until[0]
    var i = 1
    while i < active_until.len() {
        if active_until[i] > max_until {
            max_until = active_until[i]
            victim = i
        }
        i = i + 1
    }
    victim
}

func should_rematerialize_value(int32 index, int32 remat_sites, int32 call_sites, int32 value_count) bool {
    if remat_sites == 0 {
        return false
    }
    if call_sites == 0 && index < value_count / 2 {
        return false
    }
    (index % 3) != 1
}

func should_split_live_range(int32 index, int32 victim_live_until, int32 value_count, int32 call_sites, int32 blocks) bool {
    if index <= 0 {
        return false
    }
    if victim_live_until <= index + 1 {
        return false
    }
    if call_sites > 0 {
        return true
    }
    index > (value_count / 2) && blocks > 1
}

func count_live_regs(vec[int32] active_until, int32 cursor) int32 {
    var count = 0
    var i = 0
    while i < active_until.len() {
        if active_until[i] > cursor {
            count = count + 1
        }
        i = i + 1
    }
    count
}

func register_bank(string goarch) vec[string] {
    var regs = vec[string]()
    if goarch == "arm64" {
        regs.push("x9")
        regs.push("x10")
        regs.push("x11")
        regs.push("x12")
        regs.push("x13")
        regs.push("x14")
        regs.push("x15")
        return regs
    }

    regs.push("r10")
    regs.push("r11")
    regs.push("r12")
    regs.push("r13")
    regs.push("r14")
    regs.push("r15")
    regs
}

func default_options() ssa_pipeline_options {
    ssa_pipeline_options {
        enable_dce: true,
        enable_coalesce: true,
        enable_simplify_cfg: true,
        dominant_margin_override: -1,
    }
}

func apply_pipeline_rewrites(string mir_text, ssa_pass_stats pass_stats, ssa_pipeline_options options) string {
    var rewritten = mir_text

    rewritten = apply_constfold_rewrites(rewritten, pass_stats)
    rewritten = apply_gvn_rewrites(rewritten, pass_stats)
    rewritten = apply_sccp_rewrites(rewritten, pass_stats)
    rewritten = apply_pre_rewrites(rewritten, pass_stats)
    rewritten = apply_cse_rewrites(rewritten, pass_stats)
    rewritten = apply_licm_rewrites(rewritten, pass_stats)
    rewritten = apply_bce_rewrites(rewritten, pass_stats)
    rewritten = apply_cfg_rewrites(rewritten, pass_stats, options)
    rewritten = apply_invalidation_reruns(rewritten, pass_stats, options)

    rewritten
}

func build_pass_mir_trace(string mir_text, ssa_pass_stats pass_stats, ssa_pipeline_options options) string {
    var trace = "input=" + mir_text
    var current = mir_text

    var constfold = apply_constfold_rewrites(current, pass_stats)
    trace = trace + ";constfold=" + constfold
    current = constfold

    var gvn = apply_gvn_rewrites(current, pass_stats)
    trace = trace + ";gvn=" + gvn
    current = gvn

    var sccp = apply_sccp_rewrites(current, pass_stats)
    trace = trace + ";sccp=" + sccp
    current = sccp

    var pre = apply_pre_rewrites(current, pass_stats)
    trace = trace + ";pre=" + pre
    current = pre

    var cse = apply_cse_rewrites(current, pass_stats)
    trace = trace + ";cse=" + cse
    current = cse

    var licm = apply_licm_rewrites(current, pass_stats)
    trace = trace + ";licm=" + licm
    current = licm

    var bce = apply_bce_rewrites(current, pass_stats)
    trace = trace + ";bce=" + bce
    current = bce

    var cfg = apply_cfg_rewrites(current, pass_stats, options)
    trace = trace + ";cfg=" + cfg
    current = cfg

    var rerun = apply_invalidation_reruns(current, pass_stats, options)
    trace = trace + ";rerun=" + rerun
    trace
}

func build_pass_delta_trace(string mir_text, ssa_pass_stats pass_stats, ssa_pipeline_options options) string {
    var trace = ""
    var before = mir_text

    var constfold = apply_constfold_rewrites(before, pass_stats)
    trace = append_delta(trace, "constfold", before, constfold)
    before = constfold

    var gvn = apply_gvn_rewrites(before, pass_stats)
    trace = append_delta(trace, "gvn", before, gvn)
    before = gvn

    var sccp = apply_sccp_rewrites(before, pass_stats)
    trace = append_delta(trace, "sccp", before, sccp)
    before = sccp

    var pre = apply_pre_rewrites(before, pass_stats)
    trace = append_delta(trace, "pre", before, pre)
    before = pre

    var cse = apply_cse_rewrites(before, pass_stats)
    trace = append_delta(trace, "cse", before, cse)
    before = cse

    var licm = apply_licm_rewrites(before, pass_stats)
    trace = append_delta(trace, "licm", before, licm)
    before = licm

    var bce = apply_bce_rewrites(before, pass_stats)
    trace = append_delta(trace, "bce", before, bce)
    before = bce

    var cfg = apply_cfg_rewrites(before, pass_stats, options)
    trace = append_delta(trace, "cfg", before, cfg)
    before = cfg

    var rerun = apply_invalidation_reruns(before, pass_stats, options)
    trace = append_delta(trace, "rerun", before, rerun)

    trace
}

func build_pass_delta_summary(string delta_trace) string {
    if delta_trace == "" {
        return ""
    }

    var out = ""
    var cursor = 0
    while cursor < delta_trace.len() {
        var sep = find_token_from(delta_trace, ";", cursor)
        if sep > delta_trace.len() {
            sep = delta_trace.len()
        }

        var entry = slice(delta_trace, cursor, sep)
        var lb = find_token(entry, "[")
        var rb = find_token(entry, "]:")
        if lb <= entry.len() && rb <= entry.len() && rb > lb {
            var stage = slice(entry, 0, lb)
            var count = parse_delta_count(entry, lb + 1, rb)
            if out != "" {
                out = out + ","
            }
            out = out + stage + "=" + to_string(count)
        }

        if sep >= delta_trace.len() {
            break
        }
        cursor = sep + 1
    }

    out
}

func build_pass_delta_category_summary(string delta_trace, bool structural) string {
    if delta_trace == "" {
        return ""
    }

    var out = ""
    var cursor = 0
    while cursor < delta_trace.len() {
        var sep = find_token_from(delta_trace, ";", cursor)
        if sep > delta_trace.len() {
            sep = delta_trace.len()
        }

        var entry = slice(delta_trace, cursor, sep)
        var lb = find_token(entry, "[")
        var rb = find_token(entry, "]:")
        if lb <= entry.len() && rb <= entry.len() && rb > lb {
            var stage = slice(entry, 0, lb)
            var detail_start = rb + 2
            var details = ""
            if detail_start <= entry.len() {
                details = slice(entry, detail_start, entry.len())
            }
            var changed = count_delta_category_changes(details, structural)
            if out != "" {
                out = out + ","
            }
            out = out + stage + "=" + to_string(changed)
        }

        if sep >= delta_trace.len() {
            break
        }
        cursor = sep + 1
    }

    out
}

func count_delta_category_changes(string details, bool structural) int32 {
    if details == "" || details == "nochange" {
        return 0
    }

    var count = 0
    if structural {
        count = count + count_token(details, "blocks(")
        count = count + count_token(details, "stmts(")
        count = count + count_token(details, "br(")
        count = count + count_token(details, "jmp(")
    } else {
        count = count + count_token(details, "const(")
        count = count + count_token(details, "imm(")
        count = count + count_token(details, "lit(")
        count = count + count_token(details, "phi(")
        count = count + count_token(details, "memphi(")
        count = count + count_token(details, "copy(")
        count = count + count_token(details, "load(")
        count = count + count_token(details, "store(")
    }
    count
}

func build_pass_delta_hot_summary(string structural_summary, string value_summary, int32 margin_override) string {
    var structural_active = count_delta_summary_active_entries(structural_summary)
    var structural_total_passes = count_delta_summary_entries(structural_summary)
    var structural_total_changes = sum_delta_summary_counts(structural_summary)

    var value_active = count_delta_summary_active_entries(value_summary)
    var value_total_passes = count_delta_summary_entries(value_summary)
    var value_total_changes = sum_delta_summary_counts(value_summary)

    var diff = structural_total_changes - value_total_changes
    if diff < 0 {
        diff = 0 - diff
    }
    var dominant_margin = compute_dominant_margin(structural_total_changes + value_total_changes, margin_override)

    var dominant = "balanced"
    if diff > dominant_margin && structural_total_changes > value_total_changes {
        dominant = "struct"
    } else if diff > dominant_margin && value_total_changes > structural_total_changes {
        dominant = "value"
    }

    "struct=" + to_string(structural_active) + "/" + to_string(structural_total_passes)
        + "(" + to_string(structural_total_changes) + ")"
        + ",value=" + to_string(value_active) + "/" + to_string(value_total_passes)
        + "(" + to_string(value_total_changes) + ")"
        + ",margin=" + to_string(dominant_margin)
        + ",dominant=" + dominant
}

func compute_dominant_margin(int32 total_changes, int32 margin_override) int32 {
    if margin_override >= 0 {
        return margin_override
    }
    if total_changes >= 32 {
        return 3
    }
    if total_changes >= 16 {
        return 2
    }
    1
}

func count_delta_summary_entries(string summary) int32 {
    if summary == "" {
        return 0
    }

    var count = 0
    var cursor = 0
    while cursor < summary.len() {
        var sep = find_token_from(summary, ",", cursor)
        if sep > summary.len() {
            sep = summary.len()
        }
        count = count + 1
        if sep >= summary.len() {
            break
        }
        cursor = sep + 1
    }

    count
}

func count_delta_summary_active_entries(string summary) int32 {
    if summary == "" {
        return 0
    }

    var count = 0
    var cursor = 0
    while cursor < summary.len() {
        var sep = find_token_from(summary, ",", cursor)
        if sep > summary.len() {
            sep = summary.len()
        }

        var entry = slice(summary, cursor, sep)
        var eq = find_token(entry, "=")
        if eq <= entry.len() {
            var count_text = slice(entry, eq + 1, entry.len())
            if parse_delta_count(count_text, 0, count_text.len()) > 0 {
                count = count + 1
            }
        }

        if sep >= summary.len() {
            break
        }
        cursor = sep + 1
    }

    count
}

func sum_delta_summary_counts(string summary) int32 {
    if summary == "" {
        return 0
    }

    var total = 0
    var cursor = 0
    while cursor < summary.len() {
        var sep = find_token_from(summary, ",", cursor)
        if sep > summary.len() {
            sep = summary.len()
        }

        var entry = slice(summary, cursor, sep)
        var eq = find_token(entry, "=")
        if eq <= entry.len() {
            var count_text = slice(entry, eq + 1, entry.len())
            total = total + parse_delta_count(count_text, 0, count_text.len())
        }

        if sep >= summary.len() {
            break
        }
        cursor = sep + 1
    }

    total
}

func parse_delta_count(string text, int32 start, int32 end) int32 {
    var value = 0
    var i = start
    while i < end && i < text.len() {
        var ch = char_at(text, i)
        if is_digit(ch) {
            value = value * 10 + parse_digit(ch)
        }
        i = i + 1
    }
    value
}

func append_delta(string trace, string stage, string before_text, string after_text) string {
    var before = collect_mir_metrics(before_text)
    var after = collect_mir_metrics(after_text)
    var details = ""
    var changed = 0
    var r0 = append_changed_metric(details, "blocks", before.blocks, after.blocks)
    details = r0.details
    changed = changed + r0.changed
    var r1 = append_changed_metric(details, "stmts", before.stmts, after.stmts)
    details = r1.details
    changed = changed + r1.changed
    var r2 = append_changed_metric(details, "br", before.branches, after.branches)
    details = r2.details
    changed = changed + r2.changed
    var r3 = append_changed_metric(details, "jmp", before.jumps, after.jumps)
    details = r3.details
    changed = changed + r3.changed
    var r4 = append_changed_metric(details, "const", before.consts, after.consts)
    details = r4.details
    changed = changed + r4.changed
    var r5 = append_changed_metric(details, "imm", before.imms, after.imms)
    details = r5.details
    changed = changed + r5.changed
    var r6 = append_changed_metric(details, "lit", before.literals, after.literals)
    details = r6.details
    changed = changed + r6.changed
    var r7 = append_changed_metric(details, "phi", before.phi, after.phi)
    details = r7.details
    changed = changed + r7.changed
    var r8 = append_changed_metric(details, "memphi", before.memphi, after.memphi)
    details = r8.details
    changed = changed + r8.changed
    var r9 = append_changed_metric(details, "copy", before.copy, after.copy)
    details = r9.details
    changed = changed + r9.changed
    var r10 = append_changed_metric(details, "load", before.load, after.load)
    details = r10.details
    changed = changed + r10.changed
    var r11 = append_changed_metric(details, "store", before.store, after.store)
    details = r11.details
    changed = changed + r11.changed
    if changed == 0 {
        details = "nochange"
    }
    var entry = stage + "[" + to_string(changed) + "]:" + details

    if trace == "" {
        return entry
    }
    trace + ";" + entry
}

struct append_metric_result {
    string details
    int32 changed
}

func append_changed_metric(string details, string label, int32 before, int32 after) append_metric_result {
    if before == after {
        return append_metric_result {
            details: details,
            changed: 0,
        }
    }
    var part = format_metric_delta(label, before, after)
    if details == "" {
        return append_metric_result {
            details: part,
            changed: 1,
        }
    }
    append_metric_result {
        details: details + "," + part,
        changed: 1,
    }
}

func collect_mir_metrics(string mir_text) mir_metrics {
    mir_metrics {
        blocks: parse_int_after(mir_text, "blocks="),
        stmts: parse_total_stmt_count(mir_text),
        branches: count_token(mir_text, " term=branch"),
        jumps: count_token(mir_text, " term=jump"),
        consts: count_numeric_marker_total(mir_text, " const="),
        imms: count_numeric_marker_total(mir_text, " imm="),
        literals: count_numeric_marker_total(mir_text, " literal="),
        phi: count_numeric_marker_total(mir_text, " phi="),
        memphi: count_numeric_marker_total(mir_text, " memphi="),
        copy: count_numeric_marker_total(mir_text, " copy="),
        load: count_numeric_marker_total(mir_text, " load="),
        store: count_numeric_marker_total(mir_text, " store="),
    }
}

func format_metric_delta(string label, int32 before, int32 after) string {
    label + "(" + to_string(before) + "->" + to_string(after) + ")"
}

func apply_constfold_rewrites(string mir_text, ssa_pass_stats pass_stats) string {
    var rewritten = mir_text
    rewritten = reduce_numeric_marker_budget(rewritten, " const=", pass_stats.folded_constant_count)
    rewritten = reduce_numeric_marker_budget(rewritten, " imm=", pass_stats.folded_constant_count)
    rewritten = reduce_numeric_marker_budget(rewritten, " literal=", pass_stats.folded_constant_count)
    rewritten
}

func apply_gvn_rewrites(string mir_text, ssa_pass_stats pass_stats) string {
    reduce_numeric_marker_budget(mir_text, " copy=", pass_stats.gvn_rewrite_count)
}

func apply_sccp_rewrites(string mir_text, ssa_pass_stats pass_stats) string {
    normalize_stmt_counts(mir_text, pass_stats.optimized_value_count)
}

func apply_pre_rewrites(string mir_text, ssa_pass_stats pass_stats) string {
    var rewritten = mir_text
    rewritten = reduce_numeric_marker_budget(rewritten, " phi=", pass_stats.pre_eliminated_count)
    rewritten = reduce_numeric_marker_budget(rewritten, " memphi=", pass_stats.pre_eliminated_count)
    rewritten
}

func apply_cse_rewrites(string mir_text, ssa_pass_stats pass_stats) string {
    reduce_numeric_marker_budget(mir_text, " copy=", pass_stats.cse_eliminated_count)
}

func apply_licm_rewrites(string mir_text, ssa_pass_stats pass_stats) string {
    reduce_numeric_marker_budget(mir_text, " store=", pass_stats.licm_hoisted_count)
}

func apply_bce_rewrites(string mir_text, ssa_pass_stats pass_stats) string {
    reduce_numeric_marker_budget(mir_text, " load=", pass_stats.bce_removed_count)
}

func apply_cfg_rewrites(string mir_text, ssa_pass_stats pass_stats, ssa_pipeline_options options) string {
    var rewritten = mir_text
    if options.enable_simplify_cfg {
        rewritten = replace_first_n_tokens(rewritten, " term=branch", " term=jump", pass_stats.simplified_branch_count)
    }
    if options.enable_coalesce {
        rewritten = remove_empty_jump_blocks(rewritten, pass_stats.coalesced_move_count)
    }
    rewritten
}

func apply_invalidation_reruns(string mir_text, ssa_pass_stats pass_stats, ssa_pipeline_options options) string {
    if pass_stats.invalidation_rerun_count <= 0 {
        return mir_text
    }

    var rewritten = mir_text
    var reruns = pass_stats.invalidation_rerun_count

    if options.enable_simplify_cfg {
        rewritten = replace_first_n_tokens(rewritten, " term=branch", " term=jump", reruns)
    }
    if options.enable_coalesce {
        rewritten = remove_empty_jump_blocks(rewritten, reruns)
    }

    rewritten
}

func remove_empty_jump_blocks(string mir_text, int32 budget) string {
    if budget <= 0 {
        return mir_text
    }

    var out = ""
    var cursor = 0
    var removed = 0
    while cursor < mir_text.len() {
        var block_pos = find_token_from(mir_text, " | bb", cursor)
        if block_pos > mir_text.len() - 5 {
            out = out + slice(mir_text, cursor, mir_text.len())
            break
        }

        out = out + slice(mir_text, cursor, block_pos)
        var next_block = find_token_from(mir_text, " | bb", block_pos + 1)
        if next_block > mir_text.len() {
            next_block = mir_text.len()
        }
        var block_text = slice(mir_text, block_pos, next_block)
        if removed < budget && contains_token_text(block_text, " stmts=0 term=jump") {
            removed = removed + 1
        } else {
            out = out + block_text
        }
        cursor = next_block
    }

    if removed > 0 {
        out = reduce_numeric_marker_budget(out, "blocks=", removed)
    }
    out
}

func contains_token_text(string text, string needle) bool {
    find_token(text, needle) <= text.len()
}

func normalize_stmt_counts(string mir_text, int32 target_total) string {
    var current_total = parse_total_stmt_count(mir_text)
    if current_total <= 0 || target_total >= current_total {
        return mir_text
    }
    return reduce_numeric_marker_budget(mir_text, " stmts=", current_total - target_total)
}

func reduce_numeric_marker_budget(string text, string marker, int32 budget) string {
    if budget <= 0 {
        return text
    }

    var out = ""
    var cursor = 0
    var remaining = budget
    while cursor < text.len() {
        var pos = find_token_from(text, marker, cursor)
        if pos > text.len() - marker.len() {
            return out + slice(text, cursor, text.len())
        }

        out = out + slice(text, cursor, pos) + marker
        var digits_start = pos + marker.len()
        var digits_end = digits_start
        var value = 0
        while digits_end < text.len() && is_digit(char_at(text, digits_end)) {
            value = value * 10 + parse_digit(char_at(text, digits_end))
            digits_end = digits_end + 1
        }

        var reduce = 0
        if remaining > 0 && value > 0 {
            reduce = remaining
            if reduce > value {
                reduce = value
            }
        }
        out = out + to_string(value - reduce)
        remaining = remaining - reduce
        cursor = digits_end
    }

    out
}

func replace_first_n_tokens(string text, string needle, string replacement, int32 count) string {
    if count <= 0 {
        return text
    }

    var out = text
    var i = 0
    while i < count {
        var next = replace_first_token(out, needle, replacement)
        if !next.changed {
            return out
        }
        out = next.text
        i = i + 1
    }
    out
}

func find_token_from(string text, string needle, int32 start) int32 {
    var i = start
    while i <= text.len() - needle.len() {
        if slice(text, i, i + needle.len()) == needle {
            return i
        }
        i = i + 1
    }
    text.len() + 1
}

func build_dataflow_model(string mir_text, int32 block_count, int32 value_count) ssa_dataflow_model {
    var jumps = count_token(mir_text, " term=jump")
    var branches = count_token(mir_text, " term=branch")
    var calls = count_token(mir_text, " call=")
    var loads = count_numeric_marker_total(mir_text, " load=")
    if loads == 0 {
        loads = count_token(mir_text, "load")
    }
    var stores = count_numeric_marker_total(mir_text, " store=")
    if stores == 0 {
        stores = count_token(mir_text, "store")
    }
    var memphi = count_numeric_marker_total(mir_text, " memphi=")
    var edges = estimate_cfg_edges(mir_text)
    var phi = estimate_phi_nodes(mir_text)
    var alias_sets = estimate_alias_sets(mir_text, calls, loads, stores)
    var def_use = estimate_def_use_edges(value_count, edges, phi)
    var live_in = estimate_live_in_facts_with_model(block_count, edges, calls)
    var loops = estimate_loop_headers(branches, jumps)

    ssa_dataflow_model {
        block_count: block_count,
        edge_count: edges,
        value_count: value_count,
        branch_count: branches,
        jump_count: jumps,
        call_count: calls,
        load_count: loads,
        store_count: stores,
        phi_count: phi,
        memphi_count: memphi,
        alias_set_count: alias_sets,
        def_use_edges: def_use,
        live_in_facts: live_in,
        loop_headers: loops,
    }
}

func run_optimization_passes(string mir_text, ssa_dataflow_model model, ssa_pipeline_options options) ssa_pass_stats {
    var current = model.value_count
    var folded = run_constant_fold_pass(mir_text)
    current = current - folded
    if current < 1 {
        current = 1
    }

    var dce_removed = 0
    var coalesced = 0
    var simplified = 0
    var gvn_rewrites = 0
    var sccp_rewrites = 0
    var pre_eliminated = 0
    var cse_eliminated = 0
    var licm_hoisted = 0
    var bce_removed = 0
    var phi_nodes = model.phi_count
    var memory_versions = model.store_count + model.load_count
    var live_in_facts = model.live_in_facts
    var fixed_iters = 0
    var max_iters = 5
    var proof_obligations = 0
    var proof_failed = 0
    var rollback = 0
    var scheduled_passes = 0
    var blocked_passes = 0
    var dag_levels = 0
    var reruns = 0
    var rollback_points = 0
    var invalidation_reruns = 0
    var replay_steps = 0
    var scheduler_priority = 0
    var scheduler_conflicts = 0
    var cost_model_score = 0
    var solver_convergence = 100
    var stable_iters = 0
    var rollback_value = current
    var pass_dsl = build_pass_dsl(model)
    var invalidation_policy = "blocked->rerun;alias-high->gvn,sccp;loop-heavy->licm;memory-pressure->bce"
    var topology_log = ""
    var replay_log = ""
    var rollback_node = "none"

    var prev = -1
    while fixed_iters < max_iters && stable_iters < 2 {
        prev = current
        rollback_value = current
        rollback_points = rollback_points + 1

        var iter_topology = pass_topological_order(model)
        if topology_log != "" {
            topology_log = topology_log + ";"
        }
        topology_log = topology_log + "iter" + to_string(fixed_iters) + "=" + iter_topology

        var raw_gvn = run_gvn_pass(model)
        var raw_sccp = run_sccp_pass(model, current)
        var raw_pre = run_pre_pass(model)
        var raw_cse = run_cse_pass(model)
        var raw_licm = run_licm_pass(model)
        var raw_bce = run_bce_pass(model)
        scheduled_passes = scheduled_passes + 6
        dag_levels = dag_levels + pass_dag_level_count(model)
        scheduler_priority = scheduler_priority
            + pass_priority_score("gvn", model, current, fixed_iters)
            + pass_priority_score("sccp", model, current, fixed_iters)
            + pass_priority_score("pre", model, current, fixed_iters)
            + pass_priority_score("cse", model, current, fixed_iters)
            + pass_priority_score("licm", model, current, fixed_iters)
            + pass_priority_score("bce", model, current, fixed_iters)

        var gvn_node = execute_pass_node("gvn", true, raw_gvn)
        var gvn_i = gvn_node.rewrites

        var cse_node = execute_pass_node("cse", true, raw_cse)
        var cse_i = cse_node.rewrites

        var sccp_ready = pass_dependency_ready_sccp(model, gvn_i)
        var sccp_node = execute_pass_node("sccp", sccp_ready, raw_sccp)
        var sccp_i = sccp_node.rewrites
        blocked_passes = blocked_passes + sccp_node.blocked
        if sccp_node.blocked > 0 {
            rollback_node = "sccp"
            if should_auto_invalidate_pass("sccp", model, fixed_iters, blocked_passes) {
                invalidation_reruns = invalidation_reruns + 1
                sccp_node.replay_token = sccp_node.replay_token + "+invalidate"
            }
        }

        var pre_ready = pass_dependency_ready_pre(model, gvn_i, cse_i)
        var pre_node = execute_pass_node("pre", pre_ready, raw_pre)
        var pre_i = pre_node.rewrites
        blocked_passes = blocked_passes + pre_node.blocked
        if pre_node.blocked > 0 {
            rollback_node = "pre"
            if should_auto_invalidate_pass("pre", model, fixed_iters, blocked_passes) {
                invalidation_reruns = invalidation_reruns + 1
                pre_node.replay_token = pre_node.replay_token + "+invalidate"
            }
        }

        var licm_ready = pass_dependency_ready_licm(model, gvn_i + sccp_i + pre_i)
        var licm_node = execute_pass_node("licm", licm_ready, raw_licm)
        var licm_i = licm_node.rewrites
        blocked_passes = blocked_passes + licm_node.blocked
        if licm_node.blocked > 0 {
            rollback_node = "licm"
            if should_auto_invalidate_pass("licm", model, fixed_iters, blocked_passes) {
                invalidation_reruns = invalidation_reruns + 1
                licm_node.replay_token = licm_node.replay_token + "+invalidate"
            }
        }

        var bce_ready = pass_dependency_ready_bce(model)
        var bce_node = execute_pass_node("bce", bce_ready, raw_bce)
        var bce_i = bce_node.rewrites
        blocked_passes = blocked_passes + bce_node.blocked
        if bce_node.blocked > 0 {
            rollback_node = "bce"
            if should_auto_invalidate_pass("bce", model, fixed_iters, blocked_passes) {
                invalidation_reruns = invalidation_reruns + 1
                bce_node.replay_token = bce_node.replay_token + "+invalidate"
            }
        }

        if has_scheduler_conflict(pre_i, cse_i, model) {
            scheduler_conflicts = scheduler_conflicts + 1
            solver_convergence = solver_convergence - 8
            if pre_i >= cse_i {
                cse_i = 0
                cse_node.replay_token = "cse:conflict-drop"
            } else {
                pre_i = 0
                pre_node.replay_token = "pre:conflict-drop"
            }
        }

        cost_model_score = cost_model_score + evaluate_pass_cost_model(model, current, pre_i, cse_i, licm_i, bce_i)

        var iter_replay = gvn_node.replay_token
            + "," + sccp_node.replay_token
            + "," + pre_node.replay_token
            + "," + cse_node.replay_token
            + "," + licm_node.replay_token
            + "," + bce_node.replay_token
        if replay_log != "" {
            replay_log = replay_log + ";"
        }
        replay_log = replay_log + "iter" + to_string(fixed_iters) + "=" + iter_replay
        replay_steps = replay_steps + replay_step_count_from_iter(iter_replay)

        gvn_rewrites = gvn_rewrites + gvn_i
        sccp_rewrites = sccp_rewrites + sccp_i
        pre_eliminated = pre_eliminated + pre_i
        cse_eliminated = cse_eliminated + cse_i
        licm_hoisted = licm_hoisted + licm_i
        bce_removed = bce_removed + bce_i

        current = current - gvn_i - sccp_i - pre_i - cse_i
        if current < 1 {
            current = 1
        }

        if current == prev {
            stable_iters = stable_iters + 1
            solver_convergence = solver_convergence + 3
            if blocked_passes > 0 && fixed_iters + 1 < max_iters {
                reruns = reruns + 1
            }
        } else {
            stable_iters = 0
            solver_convergence = solver_convergence - 2
        }

        proof_obligations = proof_obligations + 4
        if current > prev {
            proof_failed = proof_failed + 1
        }
        fixed_iters = fixed_iters + 1
    }

    var verify_errors = verify_ssa_invariants(model)
    if verify_errors > 0 || proof_failed > 0 {
        rollback = rollback + 1
        current = rollback_value
        rollback_node = "verify"
    }

    if options.enable_dce {
        dce_removed = run_dce_pass(current, count_token(mir_text, " stmts=0"))
        current = current - dce_removed
        if current < 1 {
            current = 1
        }
    }
    if options.enable_coalesce {
        coalesced = run_coalesce_pass(current, count_token(mir_text, " term=jump"))
        current = current - coalesced
        if current < 1 {
            current = 1
        }
    }
    if options.enable_simplify_cfg {
        simplified = run_cfg_simplify_pass(current, count_token(mir_text, " term=branch"))
        current = current - simplified
        if current < 1 {
            current = 1
        }
    }

    ssa_pass_stats {
        folded_constant_count: folded,
        dce_removed_count: dce_removed,
        coalesced_move_count: coalesced,
        simplified_branch_count: simplified,
        gvn_rewrite_count: gvn_rewrites,
        sccp_rewrite_count: sccp_rewrites,
        pre_eliminated_count: pre_eliminated,
        cse_eliminated_count: cse_eliminated,
        licm_hoisted_count: licm_hoisted,
        bce_removed_count: bce_removed,
        phi_node_count: phi_nodes,
        def_use_edge_count: model.def_use_edges,
        alias_set_count: model.alias_set_count,
        memory_version_count: memory_versions,
        live_in_fact_count: live_in_facts,
        loop_header_count: model.loop_headers,
        fixed_point_iterations: fixed_iters,
        verification_error_count: verify_errors,
        rollback_count: rollback,
        proof_obligation_count: proof_obligations,
        proof_failed_count: proof_failed,
        scheduled_pass_count: scheduled_passes,
        blocked_pass_count: blocked_passes,
        dag_level_count: dag_levels,
        rerun_count: reruns,
        rollback_checkpoint_count: rollback_points,
        invalidation_rerun_count: invalidation_reruns,
        replay_step_count: replay_steps,
        scheduler_priority_score: scheduler_priority,
        scheduler_conflict_count: scheduler_conflicts,
        replay_stability_hash: hash_text(replay_log),
        cost_model_score: normalize_score(cost_model_score, 0, 1000),
        solver_convergence_score: normalize_score(solver_convergence, 0, 100),
        replay_determinism_score: replay_determinism_score(replay_log, scheduler_conflicts),
        alias_precision_level: estimate_alias_precision_level(model),
        memory_ssa_chain_count: estimate_memory_ssa_chain_count(model, pre_eliminated),
        global_value_number_count: gvn_rewrites + cse_eliminated,
        loop_proof_chain_count: estimate_loop_proof_chain_count(model, licm_hoisted, proof_obligations),
        pass_dsl: pass_dsl,
        invalidation_policy: invalidation_policy,
        pass_topology_log: topology_log,
        pass_replay_log: replay_log,
        rollback_node: rollback_node,
        optimized_value_count: current,
    }
}

func evaluate_pass_cost_model(ssa_dataflow_model model, int32 current_values, int32 pre_i, int32 cse_i, int32 licm_i, int32 bce_i) int32 {
    var value_pressure = current_values / 2
    var memory_pressure = model.load_count + model.store_count
    var reduction = pre_i + cse_i + licm_i + bce_i
    var score = reduction * 5 + model.def_use_edges - value_pressure - memory_pressure
    if score < 0 {
        return 0
    }
    score
}

func normalize_score(int32 score, int32 minv, int32 maxv) int32 {
    if score < minv {
        return minv
    }
    if score > maxv {
        return maxv
    }
    score
}

func replay_determinism_score(string replay_log, int32 conflicts) int32 {
    var base = 100 - conflicts * 10
    var iters = count_token(replay_log, "iter")
    if iters > 0 {
        base = base + 5
    }
    normalize_score(base, 0, 100)
}

func pass_priority_score(string pass_name, ssa_dataflow_model model, int32 current_values, int32 iter) int32 {
    var base = 1 + iter
    if pass_name == "gvn" {
        return base + model.def_use_edges / 4
    }
    if pass_name == "sccp" {
        return base + model.live_in_facts / 4 + model.branch_count
    }
    if pass_name == "pre" {
        return base + model.edge_count / 3
    }
    if pass_name == "cse" {
        return base + model.jump_count + model.phi_count
    }
    if pass_name == "licm" {
        return base + model.loop_headers * 2
    }
    if pass_name == "bce" {
        return base + model.load_count + model.branch_count
    }
    base + current_values / 8
}

func has_scheduler_conflict(int32 pre_i, int32 cse_i, ssa_dataflow_model model) bool {
    if pre_i <= 0 || cse_i <= 0 {
        return false
    }
    if model.edge_count <= 1 {
        return false
    }
    model.alias_set_count > 1 || model.loop_headers > 0
}

func hash_text(string text) int32 {
    var h = 17
    var i = 0
    while i < text.len() {
        h = (h * 31 + parse_digit_safe(char_at(text, i))) % 1000003
        i = i + 1
    }
    h
}

func parse_digit_safe(string ch) int32 {
    if ch >= "0" && ch <= "9" {
        return parse_digit(ch)
    }
    if ch >= "a" && ch <= "z" {
        return 10
    }
    if ch >= "A" && ch <= "Z" {
        return 11
    }
    1
}

func compute_regalloc_quality(regalloc_result allocation, int32 block_count) regalloc_quality_result {
    var spill_cost = allocation.spill_count * 4 + allocation.spill_reload_count * 2
    if spill_cost < 0 {
        spill_cost = 0
    }

    var split_quality = allocation.live_range_splits * 3 + allocation.rematerialized_values * 2 - allocation.spill_count
    if split_quality < 0 {
        split_quality = 0
    }

    var cross_block = allocation.reuse_count + allocation.max_live
    if block_count > 1 {
        cross_block = cross_block + block_count
    }

    regalloc_quality_result {
        spill_cost_score: spill_cost,
        split_quality_score: split_quality,
        cross_block_gain_score: cross_block,
    }
}

func compute_schedule_quality(ssa_pass_stats pass_stats, ssa_dataflow_model model, string goarch) schedule_quality_result {
    var throughput = pass_stats.scheduler_priority_score - pass_stats.scheduler_conflict_count * 2 + pass_stats.global_value_number_count
    if throughput < 0 {
        throughput = 0
    }

    var latency = pass_stats.loop_proof_chain_count + model.loop_headers * 2 - pass_stats.proof_failed_count * 3
    if latency < 0 {
        latency = 0
    }

    var microarch = 10
    if goarch == "arm64" {
        microarch = microarch + model.load_count + model.store_count
    } else {
        microarch = microarch + model.branch_count + model.jump_count
    }
    if microarch < 0 {
        microarch = 0
    }

    schedule_quality_result {
        throughput_score: throughput,
        latency_balance_score: latency,
        microarch_specialization_score: microarch,
    }
}

func estimate_alias_precision_level(ssa_dataflow_model model) int32 {
    var level = 1
    if model.alias_set_count > 1 {
        level = level + 1
    }
    if model.load_count + model.store_count > model.value_count / 2 {
        level = level + 1
    }
    if level > 3 {
        return 3
    }
    level
}

func estimate_memory_ssa_chain_count(ssa_dataflow_model model, int32 pre_eliminated) int32 {
    var chain = model.store_count + model.load_count + model.phi_count + model.memphi_count
    if pre_eliminated > 0 {
        chain = chain + pre_eliminated
    }
    if chain < 1 {
        return 1
    }
    chain
}

func estimate_loop_proof_chain_count(ssa_dataflow_model model, int32 licm_hoisted, int32 proof_obligations) int32 {
    var chain = model.loop_headers + licm_hoisted + proof_obligations / 4
    if chain < 1 {
        return 1
    }
    chain
}

func build_pass_dsl(ssa_dataflow_model model) string {
    var dsl = "pass gvn -> sccp,pre,cse;"
    dsl = dsl + "pass sccp requires(branch|phi|livein);"
    dsl = dsl + "pass pre requires(edges|defuse);"
    dsl = dsl + "pass licm requires(loop|memory);"
    dsl = dsl + "pass bce requires(load|branch);"
    dsl = dsl + "graph loops=" + to_string(model.loop_headers) + " alias=" + to_string(model.alias_set_count)
    dsl
}

func should_auto_invalidate_pass(string pass_name, ssa_dataflow_model model, int32 iter, int32 blocked_count) bool {
    if blocked_count <= 0 {
        return false
    }
    if pass_name == "sccp" {
        return model.alias_set_count > 1 || iter > 0
    }
    if pass_name == "pre" {
        return model.def_use_edges > model.value_count
    }
    if pass_name == "licm" {
        return model.loop_headers > 0
    }
    if pass_name == "bce" {
        return model.load_count > 0 && model.branch_count > 0
    }
    false
}

func execute_pass_node(string name, bool ready, int32 raw_rewrites) pass_node_result {
    if ready {
        return pass_node_result {
            rewrites: raw_rewrites,
            blocked: 0,
            replay_token: name + ":ok(" + to_string(raw_rewrites) + ")",
        }
    }
    if raw_rewrites > 0 {
        return pass_node_result {
            rewrites: 0,
            blocked: 1,
            replay_token: name + ":blocked",
        }
    }
    pass_node_result {
        rewrites: 0,
        blocked: 0,
        replay_token: name + ":idle",
    }
}

func replay_step_count_from_iter(string iter_replay) int32 {
    count_token(iter_replay, ",") + 1
}

func compute_debug_budget(ssa_pass_stats pass_stats, regalloc_result allocation) int32 {
    var score = 100
    score = score - pass_stats.gvn_rewrite_count
    score = score - pass_stats.sccp_rewrite_count
    score = score - pass_stats.pre_eliminated_count
    score = score - pass_stats.cse_eliminated_count
    score = score - pass_stats.licm_hoisted_count
    score = score - pass_stats.bce_removed_count
    score = score - allocation.spill_count * 2
    score = score - allocation.live_range_splits
    if pass_stats.rollback_count > 0 {
        score = score - 10
    }
    if score < 0 {
        return 0
    }
    if score > 100 {
        return 100
    }
    score
}

func pass_topological_order(ssa_dataflow_model model) string {
    var level0 = "gvn"
    var level1 = ""
    var level2 = ""

    if pass_dependency_ready_sccp(model, 0) {
        level1 = append_pass_name(level1, "sccp")
    }
    if pass_dependency_ready_pre(model, 0, 0) {
        level1 = append_pass_name(level1, "pre")
    }
    level1 = append_pass_name(level1, "cse")

    if pass_dependency_ready_licm(model, 0) {
        level2 = append_pass_name(level2, "licm")
    }
    if pass_dependency_ready_bce(model) {
        level2 = append_pass_name(level2, "bce")
    }

    "L0{" + level0 + "}->L1{" + level1 + "}->L2{" + level2 + "}"
}

func append_pass_name(string base, string name) string {
    if base == "" {
        return name
    }
    base + "," + name
}

func pass_dag_level_count(ssa_dataflow_model model) int32 {
    var levels = 1
    if model.branch_count + model.phi_count > 0 {
        levels = levels + 1
    }
    if model.loop_headers > 0 || model.load_count > 0 {
        levels = levels + 1
    }
    levels
}

func pass_dependency_ready_sccp(ssa_dataflow_model model, int32 gvn_rewrites) bool {
    if model.branch_count + model.phi_count <= 0 {
        return false
    }
    if model.live_in_facts <= 0 {
        return false
    }
    gvn_rewrites >= 0
}

func pass_dependency_ready_pre(ssa_dataflow_model model, int32 gvn_rewrites, int32 cse_rewrites) bool {
    if model.edge_count <= 1 {
        return false
    }
    if model.def_use_edges <= model.value_count {
        return false
    }
    gvn_rewrites + cse_rewrites >= 0
}

func pass_dependency_ready_licm(ssa_dataflow_model model, int32 upstream_rewrites) bool {
    if model.loop_headers <= 0 {
        return false
    }
    if model.load_count + model.store_count <= 0 {
        return false
    }
    upstream_rewrites >= 0
}

func pass_dependency_ready_bce(ssa_dataflow_model model) bool {
    model.load_count > 0 && model.branch_count > 0
}

func verify_ssa_invariants(ssa_dataflow_model model) int32 {
    var errors = 0
    if model.phi_count > model.branch_count + model.jump_count {
        errors = errors + 1
    }
    if model.def_use_edges < model.value_count {
        errors = errors + 1
    }
    if model.alias_set_count <= 0 {
        errors = errors + 1
    }
    if model.live_in_facts < model.edge_count {
        errors = errors + 1
    }
    errors
}

func run_gvn_pass(ssa_dataflow_model model) int32 {
    var candidates = model.def_use_edges / 3
    if candidates <= 1 {
        return 0
    }
    candidates / 4
}

func run_sccp_pass(ssa_dataflow_model model, int32 current_values) int32 {
    var lattice_edges = model.branch_count + model.phi_count + model.live_in_facts / 2
    if lattice_edges <= 0 {
        return 0
    }
    var reduced = lattice_edges / 6
    if reduced > current_values / 4 {
        return current_values / 4
    }
    reduced
}

func run_pre_pass(ssa_dataflow_model model) int32 {
    var candidates = model.edge_count + model.loop_headers + model.def_use_edges / 4
    if candidates <= 0 {
        return 0
    }
    candidates / 8
}

func run_cse_pass(ssa_dataflow_model model) int32 {
    var candidates = model.jump_count + model.branch_count + model.phi_count
    if candidates <= 0 {
        return 0
    }
    candidates / 2
}

func run_licm_pass(ssa_dataflow_model model) int32 {
    if model.loop_headers <= 0 {
        return 0
    }
    model.loop_headers
}

func run_bce_pass(ssa_dataflow_model model) int32 {
    var bounds_like = model.load_count + model.branch_count
    if bounds_like <= 0 {
        return 0
    }
    bounds_like / 2
}

func estimate_phi_nodes(string mir_text) int32 {
    var explicit = count_numeric_marker_total(mir_text, " phi=")
    if explicit > 0 {
        return explicit
    }
    var branches = count_token(mir_text, " term=branch")
    var joins = count_token(mir_text, " term=jump")
    branches + joins / 2
}

func count_numeric_marker_total(string text, string marker) int32 {
    var total = 0
    var cursor = 0
    while cursor < text.len() {
        var pos = find_token_from(text, marker, cursor)
        if pos > text.len() - marker.len() {
            return total
        }
        var digits = pos + marker.len()
        var value = 0
        while digits < text.len() && is_digit(char_at(text, digits)) {
            value = value * 10 + parse_digit(char_at(text, digits))
            digits = digits + 1
        }
        total = total + value
        cursor = digits
    }
    total
}

func estimate_memory_versions(string mir_text) int32 {
    count_token(mir_text, "store") + count_token(mir_text, "load")
}

func estimate_live_in_facts(string mir_text) int32 {
    var blocks = parse_int_after(mir_text, "blocks=")
    var edges = estimate_cfg_edges(mir_text)
    if blocks <= 0 {
        return edges
    }
    blocks + edges
}

func estimate_alias_sets(string mir_text, int32 calls, int32 loads, int32 stores) int32 {
    var refs = count_token(mir_text, "borrow") + count_token(mir_text, "&")
    var sets = refs + calls + (loads + stores) / 2
    if sets < 1 {
        return 1
    }
    sets
}

func estimate_def_use_edges(int32 values, int32 edges, int32 phi) int32 {
    var out = values + edges + phi * 2
    if out < values {
        return values
    }
    out
}

func estimate_live_in_facts_with_model(int32 blocks, int32 edges, int32 calls) int32 {
    var base = blocks + edges
    if calls > 0 {
        base = base + calls
    }
    if base < 1 {
        return 1
    }
    base
}

func estimate_loop_headers(int32 branches, int32 jumps) int32 {
    var loops = branches / 2 + jumps / 4
    if loops < 0 {
        return 0
    }
    loops
}

func run_constant_fold_pass(string mir_text) int32 {
    var fold_sites = count_token(mir_text, " term=return") + count_token(mir_text, " term=jump")
    if fold_sites <= 0 {
        return 0
    }
    fold_sites / 2
}

func run_dce_pass(int32 value_count, int32 empty_blocks) int32 {
    var reduced = value_count - empty_blocks
    if reduced < 0 {
        return 0
    }
    value_count - reduced
}

func run_coalesce_pass(int32 value_count, int32 jump_blocks) int32 {
    var reduce = jump_blocks / 2
    if reduce < 0 {
        return 0
    }
    if reduce > value_count {
        return value_count
    }
    reduce
}

func run_cfg_simplify_pass(int32 value_count, int32 branch_blocks) int32 {
    if branch_blocks == 0 {
        return 0
    }
    if value_count <= 1 {
        return 0
    }
    1
}

func parse_function_name(string mir_text) string {
    if !starts_with(mir_text, "mir ") {
        return "main"
    }
    var begin = 4
    var end = find_token(mir_text, " blocks=")
    if end <= begin {
        return "main"
    }
    slice(mir_text, begin, end)
}

func parse_int_after(string text, string marker) int32 {
    var start = find_token(text, marker)
    if start > text.len() {
        return 0
    }
    start = start + marker.len()
    var value = 0
    var i = start
    while i < text.len() && is_digit(char_at(text, i)) {
        var ch = char_at(text, i)
        value = value * 10 + parse_digit(ch)
        i = i + 1
    }
    value
}

func count_token(string text, string token) int32 {
    var total = 0
    var i = 0
    while i <= text.len() - token.len() {
        if slice(text, i, i + token.len()) == token {
            total = total + 1
            i = i + token.len()
        } else {
            i = i + 1
        }
    }
    total
}

func parse_total_stmt_count(string mir_text) int32 {
    var total = 0
    var marker = " stmts="
    var i = 0
    while i <= mir_text.len() - marker.len() {
        if slice(mir_text, i, i + marker.len()) == marker {
            var cursor = i + marker.len()
            var value = 0
            while cursor < mir_text.len() && is_digit(char_at(mir_text, cursor)) {
                value = value * 10 + parse_digit(char_at(mir_text, cursor))
                cursor = cursor + 1
            }
            total = total + value
            i = cursor
        } else {
            i = i + 1
        }
    }
    total
}

func estimate_cfg_edges(string mir_text) int32 {
    var jumps = count_token(mir_text, " term=jump")
    var branches = count_token(mir_text, " term=branch")
    var returns = count_token(mir_text, " term=return")
    jumps + branches * 2 + returns
}

func build_debug_lines(string mir_text, vec[string] allocated_regs) vec[string] {
    var out = vec[string]()
    var blocks = parse_int_after(mir_text, "blocks=")
    if blocks <= 0 {
        blocks = 1
    }

    var i = 0
    while i < allocated_regs.len() {
        var block = i
        while block >= blocks {
            block = block - blocks
        }
        out.push("line " + to_string(100 + i) + " -> bb" + to_string(block) + " -> " + allocated_regs[i])
        i = i + 1
    }
    out
}

func build_var_locations(vec[string] allocated_regs) vec[string] {
    var out = vec[string]()
    var i = 0
    while i < allocated_regs.len() {
        out.push("var v" + to_string(i) + " -> " + allocated_regs[i])
        i = i + 1
    }
    out
}

func dump_pipeline(ssa_program program) string {
    var out = "ssa " + program.function_name
        + " mir_opt=" + program.optimized_mir_text
        + " mir_trace=" + program.pass_mir_trace
        + " mir_delta=" + program.pass_delta_trace
        + " delta_summary=" + program.pass_delta_summary
        + " delta_struct=" + program.pass_delta_structural_summary
        + " delta_value=" + program.pass_delta_value_summary
        + " delta_hot=" + program.pass_delta_hot_summary
        + " blocks=" + to_string(program.block_count)
        + " values=" + to_string(program.value_count)
        + " opt_values=" + to_string(program.optimized_value_count)
        + " folded=" + to_string(program.folded_constant_count)
        + " dce=" + to_string(program.dce_removed_count)
        + " coalesced=" + to_string(program.coalesced_move_count)
        + " simplified=" + to_string(program.simplified_branch_count)
        + " gvn=" + to_string(program.gvn_rewrite_count)
        + " sccp=" + to_string(program.sccp_rewrite_count)
        + " pre=" + to_string(program.pre_eliminated_count)
        + " cse=" + to_string(program.cse_eliminated_count)
        + " licm=" + to_string(program.licm_hoisted_count)
        + " bce=" + to_string(program.bce_removed_count)
        + " phi=" + to_string(program.phi_node_count)
        + " defuse=" + to_string(program.def_use_edge_count)
        + " alias=" + to_string(program.alias_set_count)
        + " memv=" + to_string(program.memory_version_count)
        + " livein=" + to_string(program.live_in_fact_count)
        + " loops=" + to_string(program.loop_header_count)
        + " rewrites=" + to_string(program.semantic_rewrite_count)
        + " fix_iters=" + to_string(program.fixed_point_iterations)
        + " verify_errs=" + to_string(program.verification_error_count)
        + " rollback=" + to_string(program.rollback_count)
        + " proofs=" + to_string(program.proof_obligation_count)
        + " proof_fail=" + to_string(program.proof_failed_count)
        + " passes_sched=" + to_string(program.scheduled_pass_count)
        + " passes_blocked=" + to_string(program.blocked_pass_count)
        + " dag_levels=" + to_string(program.dag_level_count)
        + " reruns=" + to_string(program.rerun_count)
        + " rollback_pts=" + to_string(program.rollback_checkpoint_count)
        + " invalid_reruns=" + to_string(program.invalidation_rerun_count)
        + " replay_steps=" + to_string(program.replay_step_count)
        + " dbg_budget=" + to_string(program.debug_budget_score)
        + " sched_prio=" + to_string(program.scheduler_priority_score)
        + " sched_conflicts=" + to_string(program.scheduler_conflict_count)
        + " replay_hash=" + to_string(program.replay_stability_hash)
        + " alias_level=" + to_string(program.alias_precision_level)
        + " memssa_chain=" + to_string(program.memory_ssa_chain_count)
        + " gvn_total=" + to_string(program.global_value_number_count)
        + " loop_proofs=" + to_string(program.loop_proof_chain_count)
        + " spill_cost=" + to_string(program.spill_cost_score)
        + " split_quality=" + to_string(program.split_quality_score)
        + " cross_block_gain=" + to_string(program.cross_block_gain_score)
        + " sched_tp=" + to_string(program.sched_throughput_score)
        + " sched_lat=" + to_string(program.sched_latency_balance_score)
        + " microarch=" + to_string(program.microarch_specialization_score)
        + " cost_model=" + to_string(program.cost_model_score)
        + " solver_conv=" + to_string(program.solver_convergence_score)
        + " replay_det=" + to_string(program.replay_determinism_score)
        + " pass_dsl=" + program.pass_dsl
        + " inv_policy=" + program.invalidation_policy
        + " rollback_node=" + program.rollback_node
        + " pass_topo=" + program.pass_topology_log
        + " pass_replay=" + program.pass_replay_log
        + " cfg_edges=" + to_string(program.cfg_edge_count)
        + " branches=" + to_string(program.branch_block_count)
        + " spills=" + to_string(program.spill_count)
        + " reloads=" + to_string(program.spill_reload_count)
        + " call_pressure=" + to_string(program.call_pressure_event_count)
        + " splits=" + to_string(program.live_range_split_count)
        + " remat=" + to_string(program.rematerialized_value_count)
        + " reuse=" + to_string(program.regalloc_reuse_count)
        + " max_live=" + to_string(program.regalloc_max_live)
        + " dbg_lines=" + to_string(program.debug_line_count)

    var i = 0
    while i < program.allocated_regs.len() {
        out = out + " | v" + to_string(i) + "->" + program.allocated_regs[i]
        i = i + 1
    }

    out
}

func dump_debug_map(ssa_program program) string {
    var out = "ssa.debug " + program.function_name
        + " values=" + to_string(program.optimized_value_count)
        + " spills=" + to_string(program.spill_count)

    var i = 0
    while i < program.allocated_regs.len() {
        out = out + " | value#" + to_string(i) + " reg=" + program.allocated_regs[i]
        i = i + 1
    }
    i = 0
    while i < program.debug_lines.len() {
        out = out + " | " + program.debug_lines[i]
        i = i + 1
    }
    i = 0
    while i < program.debug_var_locations.len() {
        out = out + " | " + program.debug_var_locations[i]
        i = i + 1
    }
    out
}

func parse_digit(string ch) int32 {
    if ch == "0" { return 0 }
    if ch == "1" { return 1 }
    if ch == "2" { return 2 }
    if ch == "3" { return 3 }
    if ch == "4" { return 4 }
    if ch == "5" { return 5 }
    if ch == "6" { return 6 }
    if ch == "7" { return 7 }
    if ch == "8" { return 8 }
    if ch == "9" { return 9 }
    0
}

func is_digit(string ch) bool {
    ch >= "0" && ch <= "9"
}

func find_token(string text, string token) int32 {
    if token == "" {
        return 0
    }
    if text.len() < token.len() {
        return text.len() + 1
    }

    var i = 0
    while i <= text.len() - token.len() {
        if slice(text, i, i + token.len()) == token {
            return i
        }
        i = i + 1
    }
    text.len() + 1
}

func starts_with(string text, string prefix) bool {
    if text.len() < prefix.len() {
        return false
    }
    slice(text, 0, prefix.len()) == prefix
}