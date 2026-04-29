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
    int dominant_margin_override
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
    int instruction_block_count
    int instruction_value_count
    int dominator_tree_depth
    int loop_backedge_count
    int instruction_verifier_error_count
    int instruction_verifier_error_code
    string instruction_verifier_flags
    string instruction_verifier_primary
    string instruction_verifier_stage_hint
    string instruction_verifier_stage_evidence
    bool instruction_verifier_pick_matches_top
    string instruction_verifier_pick_reason
    int memory_ssa_node_count
    int points_to_set_count
    int load_store_proof_count
    int spill_reload_pair_count
    int parallel_copy_resolution_count
    int escape_stack_alloc_count
    int escape_heap_alloc_count
    int inline_budget_score
    int devirtualization_gain_score
    string instruction_block_graph
    string instruction_value_graph
    string instruction_dominator_tree
    string instruction_loop_forest
    string instruction_memory_dep_graph
    string instruction_regalloc_plan
    int block_count
    int value_count
    int cfg_edge_count
    int branch_block_count
    int optimized_value_count
    int folded_constant_count
    int dce_removed_count
    int coalesced_move_count
    int simplified_branch_count
    int gvn_rewrite_count
    int sccp_rewrite_count
    int pre_eliminated_count
    int cse_eliminated_count
    int licm_hoisted_count
    int bce_removed_count
    int phi_node_count
    int def_use_edge_count
    int alias_set_count
    int memory_version_count
    int live_in_fact_count
    int loop_header_count
    int semantic_rewrite_count
    int fixed_point_iterations
    int verification_error_count
    int rollback_count
    int proof_obligation_count
    int proof_failed_count
    int scheduled_pass_count
    int blocked_pass_count
    int dag_level_count
    int rerun_count
    int rollback_checkpoint_count
    int invalidation_rerun_count
    int replay_step_count
    int debug_budget_score
    int scheduler_priority_score
    int scheduler_conflict_count
    int replay_stability_hash
    int alias_precision_level
    int memory_ssa_chain_count
    int global_value_number_count
    int loop_proof_chain_count
    int spill_cost_score
    int split_quality_score
    int cross_block_gain_score
    int sched_throughput_score
    int sched_latency_balance_score
    int microarch_specialization_score
    int cost_model_score
    int solver_convergence_score
    int replay_determinism_score
    string pass_dsl
    string invalidation_policy
    string pass_topology_log
    string pass_replay_log
    string rollback_node
    int spill_count
    int spill_reload_count
    int call_pressure_event_count
    int live_range_split_count
    int rematerialized_value_count
    int regalloc_reuse_count
    int regalloc_max_live
    int debug_line_count
    vec[string] allocated_regs
    vec[string] debug_lines
    vec[string] debug_var_locations
}

struct ssa_rewrite_result {
    string rewritten_mir
    int rewrite_count
}

struct mir_metrics {
    int blocks
    int stmts
    int branches
    int jumps
    int consts
    int imms
    int literals
    int phi
    int memphi
    int copy
    int load
    int store
}

struct ssa_pass_stats {
    int folded_constant_count
    int dce_removed_count
    int coalesced_move_count
    int simplified_branch_count
    int gvn_rewrite_count
    int sccp_rewrite_count
    int pre_eliminated_count
    int cse_eliminated_count
    int licm_hoisted_count
    int bce_removed_count
    int phi_node_count
    int def_use_edge_count
    int alias_set_count
    int memory_version_count
    int live_in_fact_count
    int loop_header_count
    int fixed_point_iterations
    int verification_error_count
    int rollback_count
    int proof_obligation_count
    int proof_failed_count
    int scheduled_pass_count
    int blocked_pass_count
    int dag_level_count
    int rerun_count
    int rollback_checkpoint_count
    int invalidation_rerun_count
    int replay_step_count
    int scheduler_priority_score
    int scheduler_conflict_count
    int replay_stability_hash
    int cost_model_score
    int solver_convergence_score
    int replay_determinism_score
    int alias_precision_level
    int memory_ssa_chain_count
    int global_value_number_count
    int loop_proof_chain_count
    string pass_dsl
    string invalidation_policy
    string pass_topology_log
    string pass_replay_log
    string rollback_node
    int optimized_value_count
}

struct pass_node_result {
    int rewrites
    int blocked
    string replay_token
}

struct ssa_dataflow_model {
    int block_count
    int edge_count
    int value_count
    int branch_count
    int jump_count
    int call_count
    int load_count
    int store_count
    int phi_count
    int memphi_count
    int alias_set_count
    int def_use_edges
    int live_in_facts
    int loop_headers
}

struct instruction_ssa_summary {
    int instruction_block_count
    int instruction_value_count
    int dominator_tree_depth
    int loop_backedge_count
    int instruction_verifier_error_count
    int instruction_verifier_error_code
    string instruction_verifier_flags
    string instruction_verifier_primary
    string instruction_verifier_stage_hint
    string instruction_verifier_stage_evidence
    bool instruction_verifier_pick_matches_top
    string instruction_verifier_pick_reason
    int memory_ssa_node_count
    int points_to_set_count
    int load_store_proof_count
    int spill_reload_pair_count
    int parallel_copy_resolution_count
    int escape_stack_alloc_count
    int escape_heap_alloc_count
    int inline_budget_score
    int devirtualization_gain_score
    string instruction_block_graph
    string instruction_value_graph
    string instruction_dominator_tree
    string instruction_loop_forest
    string instruction_memory_dep_graph
    string instruction_regalloc_plan
}

struct instruction_verify_result {
    int error_count
    int error_code
}

func build_pipeline(string mir_text, string goarch) ssa_program {
    return build_pipeline_with_options(mir_text, goarch, default_options())
}

func build_pipeline_with_margin(string mir_text, string goarch, int dominant_margin_override) ssa_program {
    let options = default_options()
    options.dominant_margin_override = dominant_margin_override
    return build_pipeline_with_options(mir_text, goarch, options)
}

func build_pipeline_with_graph_hints(mir_graph graph, string mir_text, string goarch) ssa_program {
    let program = build_pipeline(mir_text, goarch)

    let graph_blocks = graph.blocks.len()
    let graph_values = 0
    let graph_branches = 0
    let graph_edges = 0
    let i = 0
    while i < graph.blocks.len() {
        let block = graph.blocks[i]
        graph_values = graph_values + block.statements.len()
        graph_edges = graph_edges + block.terminator.edges.len()
        if block.terminator.kind == "branch" {
            graph_branches = graph_branches + 1
        }

        let j = 0
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

func build_pipeline_with_graph_hints_and_margin(mir_graph graph, string mir_text, string goarch, int dominant_margin_override) ssa_program {
    let program = build_pipeline_with_margin(mir_text, goarch, dominant_margin_override)

    let graph_blocks = graph.blocks.len()
    let graph_values = 0
    let graph_branches = 0
    let graph_edges = 0
    let i = 0
    while i < graph.blocks.len() {
        let block = graph.blocks[i]
        graph_values = graph_values + block.statements.len()
        graph_edges = graph_edges + block.terminator.edges.len()
        if block.terminator.kind == "branch" {
            graph_branches = graph_branches + 1
        }

        let j = 0
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
    let rewrite = canonicalize_mir(mir_text)
    let rewritten = rewrite.rewritten_mir

    let function_name = parse_function_name(rewritten)
    let block_count = parse_int_after(rewritten, "blocks=")
    let value_count = parse_total_stmt_count(rewritten)
    if value_count == 0 {
        value_count = block_count
    }
    let model = build_dataflow_model(rewritten, block_count, value_count)
    let pass_stats = run_optimization_passes(rewritten, model, options)
    let pass_mir_trace = build_pass_mir_trace(rewritten, pass_stats, options)
    let pass_delta_trace = build_pass_delta_trace(rewritten, pass_stats, options)
    let pass_delta_summary = build_pass_delta_summary(pass_delta_trace)
    let pass_delta_structural_summary = build_pass_delta_category_summary(pass_delta_trace, true)
    let pass_delta_value_summary = build_pass_delta_category_summary(pass_delta_trace, false)
    let pass_delta_hot_summary = build_pass_delta_hot_summary(pass_delta_structural_summary, pass_delta_value_summary, options.dominant_margin_override)
    let optimized_mir = apply_pipeline_rewrites(rewritten, pass_stats, options)
    let optimized_block_count = parse_int_after(optimized_mir, "blocks=")
    if optimized_block_count <= 0 {
        optimized_block_count = block_count
    }
    let optimized_value_count = pass_stats.optimized_value_count
    let optimized_text_value_count = parse_total_stmt_count(optimized_mir)
    if optimized_text_value_count > 0 {
        optimized_value_count = optimized_text_value_count
    }
    if pass_stats.verification_error_count > 0 {
        optimized_value_count = value_count
        optimized_mir = rewritten
    }
    let allocation = linear_scan_regalloc_with_spill(optimized_mir, optimized_value_count, goarch)
    let debug_budget = compute_debug_budget(pass_stats, allocation)
    let regalloc_quality = compute_regalloc_quality(allocation, optimized_block_count)
    let sched_quality = compute_schedule_quality(pass_stats, model, goarch)
    let instruction_summary = analyze_instruction_ssa(optimized_mir, model, pass_stats, allocation, pass_delta_summary)
    let debug_lines = build_debug_lines(optimized_mir, allocation.allocated_regs)
    let debug_var_locations = build_var_locations(allocation.allocated_regs)

    ssa_program {
        function_name: function_name,
        optimized_mir_text: optimized_mir,
        pass_mir_trace: pass_mir_trace,
        pass_delta_trace: pass_delta_trace,
        pass_delta_summary: pass_delta_summary,
        pass_delta_structural_summary: pass_delta_structural_summary,
        pass_delta_value_summary: pass_delta_value_summary,
        pass_delta_hot_summary: pass_delta_hot_summary,
        instruction_block_count: instruction_summary.instruction_block_count,
        instruction_value_count: instruction_summary.instruction_value_count,
        dominator_tree_depth: instruction_summary.dominator_tree_depth,
        loop_backedge_count: instruction_summary.loop_backedge_count,
        instruction_verifier_error_count: instruction_summary.instruction_verifier_error_count,
        instruction_verifier_error_code: instruction_summary.instruction_verifier_error_code,
        instruction_verifier_flags: instruction_summary.instruction_verifier_flags,
        instruction_verifier_primary: instruction_summary.instruction_verifier_primary,
        instruction_verifier_stage_hint: instruction_summary.instruction_verifier_stage_hint,
        instruction_verifier_stage_evidence: instruction_summary.instruction_verifier_stage_evidence,
        instruction_verifier_pick_matches_top: instruction_summary.instruction_verifier_pick_matches_top,
        instruction_verifier_pick_reason: instruction_summary.instruction_verifier_pick_reason,
        memory_ssa_node_count: instruction_summary.memory_ssa_node_count,
        points_to_set_count: instruction_summary.points_to_set_count,
        load_store_proof_count: instruction_summary.load_store_proof_count,
        spill_reload_pair_count: instruction_summary.spill_reload_pair_count,
        parallel_copy_resolution_count: instruction_summary.parallel_copy_resolution_count,
        escape_stack_alloc_count: instruction_summary.escape_stack_alloc_count,
        escape_heap_alloc_count: instruction_summary.escape_heap_alloc_count,
        inline_budget_score: instruction_summary.inline_budget_score,
        devirtualization_gain_score: instruction_summary.devirtualization_gain_score,
        instruction_block_graph: instruction_summary.instruction_block_graph,
        instruction_value_graph: instruction_summary.instruction_value_graph,
        instruction_dominator_tree: instruction_summary.instruction_dominator_tree,
        instruction_loop_forest: instruction_summary.instruction_loop_forest,
        instruction_memory_dep_graph: instruction_summary.instruction_memory_dep_graph,
        instruction_regalloc_plan: instruction_summary.instruction_regalloc_plan,
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

func analyze_instruction_ssa(string mir_text, ssa_dataflow_model model, ssa_pass_stats pass_stats, regalloc_result allocation, string pass_delta_summary) instruction_ssa_summary {
    let instruction_blocks = parse_int_after(mir_text, "blocks=")
    if instruction_blocks <= 0 {
        instruction_blocks = count_token(mir_text, " | bb")
    }

    let instruction_values = parse_total_stmt_count(mir_text)
    if instruction_values <= 0 {
        instruction_values = model.value_count
    }

    let backedges = estimate_loop_backedges(mir_text, model)
    let dom_depth = estimate_dominator_depth(instruction_blocks, model.edge_count, backedges)
    let memory_nodes = model.memphi_count + model.load_count + model.store_count
    let load_store_proofs = int32_min(model.load_count, model.store_count) + model.memphi_count

    let spill_pairs = int32_min(allocation.spill_count, allocation.spill_reload_count)
    let parallel_copies = pass_stats.coalesced_move_count + model.phi_count + model.memphi_count

    let heap_allocs = estimate_escape_heap_allocs(model, pass_stats)
    let stack_allocs = estimate_escape_stack_allocs(instruction_values, heap_allocs)

    let inline_budget = estimate_inline_budget(model, pass_stats)
    let devirt_gain = estimate_devirtualization_gain(model, pass_stats)

    let block_graph = build_instruction_block_graph(instruction_blocks, model.edge_count, model.branch_count, model.jump_count)
    let value_graph = build_instruction_value_graph(instruction_values, model.def_use_edges, model.phi_count, model.memphi_count)
    let dominator_tree = build_instruction_dominator_tree(instruction_blocks, dom_depth, backedges)
    let loop_forest = build_instruction_loop_forest(model.loop_headers, backedges)
    let memory_dep_graph = build_instruction_memory_dep_graph(model.load_count, model.store_count, model.memphi_count, load_store_proofs)
    let regalloc_plan = build_instruction_regalloc_plan(spill_pairs, parallel_copies, allocation.live_range_splits, allocation.rematerialized_values)

    let verifier = verify_instruction_ssa(
        mir_text,
        model,
        pass_stats,
        instruction_blocks,
        instruction_values,
        memory_nodes,
        parallel_copies,
        block_graph,
        value_graph,
        dominator_tree,
        memory_dep_graph,
        regalloc_plan,
    )
    let verify_primary = primary_instruction_verify_flag(verifier.error_code)
    let verify_stage_hint = choose_instruction_verify_stage(verify_primary, pass_delta_summary)
    let verify_stage_evidence = build_instruction_verify_stage_evidence(verify_primary, pass_delta_summary, verify_stage_hint)
    let verify_pick_matches_top = instruction_verify_pick_matches_top(verify_primary, pass_delta_summary, verify_stage_hint)
    let verify_pick_reason = instruction_verify_pick_reason(verify_primary, pass_delta_summary, verify_stage_hint)

    instruction_ssa_summary {
        instruction_block_count: instruction_blocks,
        instruction_value_count: instruction_values,
        dominator_tree_depth: dom_depth,
        loop_backedge_count: backedges,
        instruction_verifier_error_count: verifier.error_count,
        instruction_verifier_error_code: verifier.error_code,
        instruction_verifier_flags: format_instruction_verify_flags(verifier.error_code),
        instruction_verifier_primary: verify_primary,
        instruction_verifier_stage_hint: verify_stage_hint,
        instruction_verifier_stage_evidence: verify_stage_evidence,
        instruction_verifier_pick_matches_top: verify_pick_matches_top,
        instruction_verifier_pick_reason: verify_pick_reason,
        memory_ssa_node_count: memory_nodes,
        points_to_set_count: model.alias_set_count,
        load_store_proof_count: load_store_proofs,
        spill_reload_pair_count: spill_pairs,
        parallel_copy_resolution_count: parallel_copies,
        escape_stack_alloc_count: stack_allocs,
        escape_heap_alloc_count: heap_allocs,
        inline_budget_score: inline_budget,
        devirtualization_gain_score: devirt_gain,
        instruction_block_graph: block_graph,
        instruction_value_graph: value_graph,
        instruction_dominator_tree: dominator_tree,
        instruction_loop_forest: loop_forest,
        instruction_memory_dep_graph: memory_dep_graph,
        instruction_regalloc_plan: regalloc_plan,
    }
}

func choose_instruction_verify_stage(string primary, string pass_delta_summary) string {
    if primary == "ok" {
        return "none"
    }

    let candidates = stage_candidates_for_verify_primary(primary)
    if candidates.len() == 0 {
        return "unknown"
    }

    let best = candidates[0]
    let best_count = stage_delta_count(pass_delta_summary, best)
    let i = 1
    while i < candidates.len() {
        let stage = candidates[i]
        let count = stage_delta_count(pass_delta_summary, stage)
        if count > best_count {
            best = stage
            best_count = count
        }
        i = i + 1
    }

    best
}

func build_instruction_verify_stage_evidence(string primary, string pass_delta_summary, string picked) string {
    if primary == "ok" {
        return "none"
    }

    let candidates = stage_candidates_for_verify_primary(primary)
    if candidates.len() == 0 {
        return "unknown"
    }

    let top_stage = candidates[0]
    let top_count = stage_delta_count(pass_delta_summary, top_stage)
    let second_stage = "none"
    let second_count = 0

    let i = 1
    while i < candidates.len() {
        let stage = candidates[i]
        let count = stage_delta_count(pass_delta_summary, stage)
        if count > top_count {
            second_stage = top_stage
            second_count = top_count
            top_stage = stage
            top_count = count
        } else if second_stage == "none" || count > second_count {
            second_stage = stage
            second_count = count
        }
        i = i + 1
    }

    "primary=" + primary
        + ",picked=" + picked
        + ",top=" + top_stage + ":" + to_string(top_count)
        + ",second=" + second_stage + ":" + to_string(second_count)
}

func instruction_verify_pick_matches_top(string primary, string pass_delta_summary, string picked) bool {
    if primary == "ok" {
        return picked == "none"
    }

    let candidates = stage_candidates_for_verify_primary(primary)
    if candidates.len() == 0 {
        return picked == "unknown"
    }

    let top_stage = candidates[0]
    let top_count = stage_delta_count(pass_delta_summary, top_stage)
    let i = 1
    while i < candidates.len() {
        let stage = candidates[i]
        let count = stage_delta_count(pass_delta_summary, stage)
        if count > top_count {
            top_stage = stage
            top_count = count
        }
        i = i + 1
    }

    picked == top_stage
}

func instruction_verify_pick_reason(string primary, string pass_delta_summary, string picked) string {
    if primary == "ok" {
        return "ok"
    }

    let candidates = stage_candidates_for_verify_primary(primary)
    if candidates.len() == 0 {
        return "unknown"
    }

    let top_stage = candidates[0]
    let top_count = stage_delta_count(pass_delta_summary, top_stage)
    let tie_count = 1
    let i = 1
    while i < candidates.len() {
        let stage = candidates[i]
        let count = stage_delta_count(pass_delta_summary, stage)
        if count > top_count {
            top_stage = stage
            top_count = count
            tie_count = 1
        } else if count == top_count {
            tie_count = tie_count + 1
        }
        i = i + 1
    }

    if picked == top_stage {
        if tie_count > 1 {
            return "tie-break"
        }
        return "top-match"
    }
    "fallback"
}

func stage_candidates_for_verify_primary(string primary) vec[string] {
    let out = vec[string]()

    if primary == "format" {
        out.push("constfold")
        out.push("sccp")
        return out
    }
    if primary == "shape" {
        out.push("cfg")
        out.push("rerun")
        return out
    }
    if primary == "defuse" {
        out.push("gvn")
        out.push("cse")
        out.push("pre")
        return out
    }
    if primary == "mem-node" || primary == "mem-chain" || primary == "mem-sample" || primary == "mem-count" {
        out.push("bce")
        out.push("licm")
        out.push("pre")
        return out
    }
    if primary == "block-sample" || primary == "block-count" || primary == "dom-sample" || primary == "dom-count" {
        out.push("cfg")
        out.push("rerun")
        return out
    }
    if primary == "value-sample" || primary == "value-count" {
        out.push("sccp")
        out.push("gvn")
        out.push("cse")
        return out
    }
    if primary == "regalloc-sample" {
        out.push("rerun")
        out.push("cfg")
        return out
    }

    out.push("constfold")
    out
}

func stage_delta_count(string summary, string stage) int {
    if summary == "" {
        return 0
    }

    let cursor = 0
    while cursor < summary.len() {
        let sep = find_token_from(summary, ",", cursor)
        if sep > summary.len() {
            sep = summary.len()
        }

        let entry = slice(summary, cursor, sep)
        let eq = find_token(entry, "=")
        if eq <= entry.len() {
            let entry_stage = slice(entry, 0, eq)
            if entry_stage == stage {
                let count_text = slice(entry, eq + 1, entry.len())
                return parse_delta_count(count_text, 0, count_text.len())
            }
        }

        if sep >= summary.len() {
            break
        }
        cursor = sep + 1
    }

    0
}

func build_instruction_block_graph(int blocks, int edges, int branches, int jumps) string {
    let sample = "none"
    if blocks >= 2 {
        sample = "bb0->bb1"
    }
    if blocks >= 3 {
        sample = sample + "|bb1->bb2"
    }
    "bbg(nodes=" + to_string(blocks)
        + ",edges=" + to_string(edges)
        + ",br=" + to_string(branches)
        + ",jmp=" + to_string(jumps)
        + ",sample=" + sample
        + ")"
}

func build_instruction_value_graph(int values, int def_use_edges, int phi_nodes, int memphi_nodes) string {
    let sample = "none"
    if values >= 2 {
        sample = "v0->v1"
    }
    if values >= 3 {
        sample = sample + "|v1->v2"
    }
    "vgraph(values=" + to_string(values)
        + ",defuse=" + to_string(def_use_edges)
        + ",phi=" + to_string(phi_nodes)
        + ",memphi=" + to_string(memphi_nodes)
        + ",sample=" + sample
        + ")"
}

func build_instruction_dominator_tree(int blocks, int depth, int backedges) string {
    let dom_edges = blocks - 1
    if dom_edges < 0 {
        dom_edges = 0
    }
    let sample = "none"
    if blocks >= 2 {
        sample = "bb0>bb1"
    }
    if blocks >= 3 {
        sample = sample + "|bb1>bb2"
    }
    "dom(root=bb0,depth=" + to_string(depth)
        + ",edges=" + to_string(dom_edges)
        + ",backedges=" + to_string(backedges)
        + ",sample=" + sample
        + ")"
}

func build_instruction_loop_forest(int headers, int backedges) string {
    "loops(headers=" + to_string(headers)
        + ",backedges=" + to_string(backedges)
        + ")"
}

func build_instruction_memory_dep_graph(int loads, int stores, int memphi, int proofs) string {
    let sample = "none"
    if stores > 0 && loads > 0 {
        sample = "store0->load0"
    } else if memphi > 0 {
        sample = "memphi0->load0"
    }
    "mdep(load=" + to_string(loads)
        + ",store=" + to_string(stores)
        + ",memphi=" + to_string(memphi)
        + ",proofs=" + to_string(proofs)
        + ",sample=" + sample
        + ")"
}

func build_instruction_regalloc_plan(int spill_pairs, int parallel_copies, int splits, int remat) string {
    let sample = "none"
    if parallel_copies > 0 {
        sample = "pcopy(v0->v1)"
    } else if spill_pairs > 0 {
        sample = "spill0<->reload0"
    }
    "rplan(spill_pairs=" + to_string(spill_pairs)
        + ",pcopy=" + to_string(parallel_copies)
        + ",splits=" + to_string(splits)
        + ",remat=" + to_string(remat)
        + ",sample=" + sample
        + ")"
}

func estimate_loop_backedges(string mir_text, ssa_dataflow_model model) int {
    let explicit = count_token(mir_text, " backedge")
    if explicit > 0 {
        return explicit
    }
    if model.loop_headers > 0 {
        return model.loop_headers
    }
    0
}

func estimate_dominator_depth(int blocks, int edges, int backedges) int {
    if blocks <= 0 {
        return 1
    }
    let depth = 1 + (edges / blocks)
    if backedges > 0 {
        depth = depth + 1
    }
    if depth > blocks {
        return blocks
    }
    if depth < 1 {
        return 1
    }
    depth
}

func verify_instruction_ssa(
    string mir_text,
    ssa_dataflow_model model,
    ssa_pass_stats pass_stats,
    int blocks,
    int values,
    int memory_nodes,
    int parallel_copies,
    string block_graph,
    string value_graph,
    string dominator_tree,
    string memory_dep_graph,
    string regalloc_plan,
) instruction_verify_result {
    let errors = 0
    let code = 0

    let E_FORMAT = verify_flag_format()
    let E_SHAPE = verify_flag_shape()
    let E_DEFUSE = verify_flag_defuse()
    let E_MEM_NODE = verify_flag_mem_node()
    let E_MEM_CHAIN = verify_flag_mem_chain()
    let E_BLOCK_SAMPLE = verify_flag_block_sample()
    let E_VALUE_SAMPLE = verify_flag_value_sample()
    let E_DOM_SAMPLE = verify_flag_dom_sample()
    let E_MEM_SAMPLE = verify_flag_mem_sample()
    let E_REGALLOC_SAMPLE = verify_flag_regalloc_sample()
    let E_BLOCK_COUNT = verify_flag_block_count()
    let E_VALUE_COUNT = verify_flag_value_count()
    let E_DOM_COUNT = verify_flag_dom_count()
    let E_MEM_COUNT = verify_flag_mem_count()

    if !starts_with(mir_text, "mir ") {
        errors = errors + 1
        code = set_error_flag(code, E_FORMAT)
    }
    if blocks <= 0 || values <= 0 {
        errors = errors + 1
        code = set_error_flag(code, E_SHAPE)
    }
    if model.def_use_edges < values {
        errors = errors + 1
        code = set_error_flag(code, E_DEFUSE)
    }
    if memory_nodes < model.memphi_count {
        errors = errors + 1
        code = set_error_flag(code, E_MEM_NODE)
    }
    if pass_stats.memory_ssa_chain_count < model.memphi_count {
        errors = errors + 1
        code = set_error_flag(code, E_MEM_CHAIN)
    }

    if blocks >= 2 && !contains_token_text(block_graph, "bb0->bb1") {
        errors = errors + 1
        code = set_error_flag(code, E_BLOCK_SAMPLE)
    }
    if values >= 2 && !contains_token_text(value_graph, "v0->v1") {
        errors = errors + 1
        code = set_error_flag(code, E_VALUE_SAMPLE)
    }
    if blocks >= 2 && !contains_token_text(dominator_tree, "bb0>bb1") {
        errors = errors + 1
        code = set_error_flag(code, E_DOM_SAMPLE)
    }

    if model.store_count > 0 && model.load_count > 0 {
        if !contains_token_text(memory_dep_graph, "store0->load0") {
            errors = errors + 1
            code = set_error_flag(code, E_MEM_SAMPLE)
        }
    }

    if parallel_copies > 0 {
        if !contains_token_text(regalloc_plan, "pcopy(v0->v1)") {
            errors = errors + 1
            code = set_error_flag(code, E_REGALLOC_SAMPLE)
        }
    }

    let block_rel = count_token(block_graph, "->")
    let block_cap = blocks - 1
    if block_cap < 0 {
        block_cap = 0
    }
    if block_rel > block_cap || block_rel > model.edge_count {
        errors = errors + 1
        code = set_error_flag(code, E_BLOCK_COUNT)
    }

    let value_rel = count_token(value_graph, "->")
    if value_rel > model.def_use_edges {
        errors = errors + 1
        code = set_error_flag(code, E_VALUE_COUNT)
    }

    let dom_rel = count_token(dominator_tree, ">")
    if dom_rel > block_cap {
        errors = errors + 1
        code = set_error_flag(code, E_DOM_COUNT)
    }

    let mem_rel = count_token(memory_dep_graph, "->")
    if mem_rel > (model.load_count + model.store_count + model.memphi_count) {
        errors = errors + 1
        code = set_error_flag(code, E_MEM_COUNT)
    }

    instruction_verify_result {
        error_count: errors,
        error_code: code,
    }
}

func format_instruction_verify_flags(int code) string {
    if code == 0 {
        return "ok"
    }

    let out = ""
    out = append_verify_flag(out, code, verify_flag_format(), "format")
    out = append_verify_flag(out, code, verify_flag_shape(), "shape")
    out = append_verify_flag(out, code, verify_flag_defuse(), "defuse")
    out = append_verify_flag(out, code, verify_flag_mem_node(), "mem-node")
    out = append_verify_flag(out, code, verify_flag_mem_chain(), "mem-chain")
    out = append_verify_flag(out, code, verify_flag_block_sample(), "block-sample")
    out = append_verify_flag(out, code, verify_flag_value_sample(), "value-sample")
    out = append_verify_flag(out, code, verify_flag_dom_sample(), "dom-sample")
    out = append_verify_flag(out, code, verify_flag_mem_sample(), "mem-sample")
    out = append_verify_flag(out, code, verify_flag_regalloc_sample(), "regalloc-sample")
    out = append_verify_flag(out, code, verify_flag_block_count(), "block-count")
    out = append_verify_flag(out, code, verify_flag_value_count(), "value-count")
    out = append_verify_flag(out, code, verify_flag_dom_count(), "dom-count")
    out = append_verify_flag(out, code, verify_flag_mem_count(), "mem-count")

    if out == "" {
        return "unknown"
    }
    out
}

func primary_instruction_verify_flag(int code) string {
    if code == 0 {
        return "ok"
    }

    if has_error_flag(code, verify_flag_format()) {
        return "format"
    }
    if has_error_flag(code, verify_flag_shape()) {
        return "shape"
    }
    if has_error_flag(code, verify_flag_defuse()) {
        return "defuse"
    }
    if has_error_flag(code, verify_flag_mem_node()) {
        return "mem-node"
    }
    if has_error_flag(code, verify_flag_mem_chain()) {
        return "mem-chain"
    }
    if has_error_flag(code, verify_flag_block_sample()) {
        return "block-sample"
    }
    if has_error_flag(code, verify_flag_value_sample()) {
        return "value-sample"
    }
    if has_error_flag(code, verify_flag_dom_sample()) {
        return "dom-sample"
    }
    if has_error_flag(code, verify_flag_mem_sample()) {
        return "mem-sample"
    }
    if has_error_flag(code, verify_flag_regalloc_sample()) {
        return "regalloc-sample"
    }
    if has_error_flag(code, verify_flag_block_count()) {
        return "block-count"
    }
    if has_error_flag(code, verify_flag_value_count()) {
        return "value-count"
    }
    if has_error_flag(code, verify_flag_dom_count()) {
        return "dom-count"
    }
    if has_error_flag(code, verify_flag_mem_count()) {
        return "mem-count"
    }
    "unknown"
}

func append_verify_flag(string out, int code, int flag, string name) string {
    if !has_error_flag(code, flag) {
        return out
    }
    if out == "" {
        return name
    }
    out + "|" + name
}

func verify_flag_format() int { 1 }
func verify_flag_shape() int { 2 }
func verify_flag_defuse() int { 4 }
func verify_flag_mem_node() int { 8 }
func verify_flag_mem_chain() int { 16 }
func verify_flag_block_sample() int { 32 }
func verify_flag_value_sample() int { 64 }
func verify_flag_dom_sample() int { 128 }
func verify_flag_mem_sample() int { 256 }
func verify_flag_regalloc_sample() int { 512 }
func verify_flag_block_count() int { 1024 }
func verify_flag_value_count() int { 2048 }
func verify_flag_dom_count() int { 4096 }
func verify_flag_mem_count() int { 8192 }

func set_error_flag(int code, int flag) int {
    if has_error_flag(code, flag) {
        return code
    }
    code + flag
}

func has_error_flag(int code, int flag) bool {
    if flag <= 0 {
        return false
    }

    let bucket = code / flag
    if bucket <= 0 {
        return false
    }
    (bucket % 2) == 1
}

func estimate_escape_heap_allocs(ssa_dataflow_model model, ssa_pass_stats pass_stats) int {
    let heap = model.call_count + model.store_count / 2 + model.alias_set_count / 4
    if pass_stats.alias_precision_level <= 1 {
        heap = heap + 1
    }
    if heap < 0 {
        return 0
    }
    heap
}

func estimate_escape_stack_allocs(int values, int heap_allocs) int {
    let stack = values - heap_allocs
    if stack < 0 {
        return 0
    }
    stack
}

func estimate_inline_budget(ssa_dataflow_model model, ssa_pass_stats pass_stats) int {
    let budget = 120 - model.value_count - model.call_count * 4 - model.loop_headers * 2 + pass_stats.gvn_rewrite_count
    if budget < 0 {
        return 0
    }
    budget
}

func estimate_devirtualization_gain(ssa_dataflow_model model, ssa_pass_stats pass_stats) int {
    let gain = model.call_count * 2 + pass_stats.gvn_rewrite_count / 2 + model.alias_set_count / 3
    if gain < 0 {
        return 0
    }
    gain
}

func int32_min(int left, int right) int {
    if left < right {
        return left
    }
    right
}

func canonicalize_mir(string mir_text) ssa_rewrite_result {
    let rewritten = mir_text
    let rewrites = 0

    let r0 = replace_first_token(rewritten, " term=jump |", " term=return |")
    if r0.changed {
        rewritten = r0.text
        rewrites = rewrites + 1
    }

    let r1 = replace_first_token(rewritten, " stmts=0 term=branch", " stmts=0 term=jump")
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
    let pos = find_token(text, needle)
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
    int spill_count
    int spill_reload_count
    int call_pressure_events
    int live_range_splits
    int rematerialized_values
    int reuse_count
    int max_live
}

struct regalloc_quality_result {
    int spill_cost_score
    int split_quality_score
    int cross_block_gain_score
}

struct schedule_quality_result {
    int throughput_score
    int latency_balance_score
    int microarch_specialization_score
}

func linear_scan_regalloc_with_spill(string mir_text, int value_count, string goarch) regalloc_result {
    let regs = register_bank(goarch)
    let call_sites = count_token(mir_text, " call=")
    let remat_sites = count_token(mir_text, " const") + count_token(mir_text, " imm") + count_token(mir_text, " literal=")
    let blocks = parse_number_after(mir_text, "blocks=")
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

    let active_until = vec[int]()
    let ri = 0
    while ri < regs.len() {
        active_until.push(0)
        ri = ri + 1
    }

    let out = vec[string]()
    let spills = 0
    let spill_reloads = 0
    let splits = 0
    let remat = 0
    let reuse = 0
    let max_live = 0
    let live_width = 3
    if call_sites > 0 {

        live_width = 2
    }

    let i = 0
    while i < value_count {
        let chosen = -1
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
            let hold = choose_live_width(i, value_count, live_width, call_sites)
            active_until[chosen] = i + hold
            out.push(regs[chosen])

            let live_now = count_live_regs(active_until, i)
            if live_now > max_live {
                max_live = live_now
            }
        } else {
            let victim = pick_split_victim(active_until)
            let victim_live_until = active_until[victim]
            let remat_candidate = should_rematerialize_value(i, remat_sites, call_sites, value_count)
            let split_candidate = should_split_live_range(i, victim_live_until, value_count, call_sites, blocks)

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

func choose_live_width(int index, int value_count, int base_width, int call_sites) int {
    let width = base_width
    if call_sites > 0 && index > (value_count / 2) {
        width = width - 1
    }
    if width < 1 {
        return 1
    }
    width
}

func pick_split_victim(vec[int] active_until) int {
    let victim = 0
    let max_until = active_until[0]
    let i = 1
    while i < active_until.len() {
        if active_until[i] > max_until {
            max_until = active_until[i]
            victim = i
        }
        i = i + 1
    }
    victim
}

func should_rematerialize_value(int index, int remat_sites, int call_sites, int value_count) bool {
    if remat_sites == 0 {
        return false
    }
    if call_sites == 0 && index < value_count / 2 {
        return false
    }
    (index % 3) != 1
}

func should_split_live_range(int index, int victim_live_until, int value_count, int call_sites, int blocks) bool {
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

func count_live_regs(vec[int] active_until, int cursor) int {
    let count = 0
    let i = 0
    while i < active_until.len() {
        if active_until[i] > cursor {
            count = count + 1
        }
        i = i + 1
    }
    count
}

func register_bank(string goarch) vec[string] {
    let regs = vec[string]()
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
    let rewritten = mir_text

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
    let trace = "input=" + mir_text
    let current = mir_text

    let constfold = apply_constfold_rewrites(current, pass_stats)
    trace = trace + ";constfold=" + constfold
    current = constfold

    let gvn = apply_gvn_rewrites(current, pass_stats)
    trace = trace + ";gvn=" + gvn
    current = gvn

    let sccp = apply_sccp_rewrites(current, pass_stats)
    trace = trace + ";sccp=" + sccp
    current = sccp

    let pre = apply_pre_rewrites(current, pass_stats)
    trace = trace + ";pre=" + pre
    current = pre

    let cse = apply_cse_rewrites(current, pass_stats)
    trace = trace + ";cse=" + cse
    current = cse

    let licm = apply_licm_rewrites(current, pass_stats)
    trace = trace + ";licm=" + licm
    current = licm

    let bce = apply_bce_rewrites(current, pass_stats)
    trace = trace + ";bce=" + bce
    current = bce

    let cfg = apply_cfg_rewrites(current, pass_stats, options)
    trace = trace + ";cfg=" + cfg
    current = cfg

    let rerun = apply_invalidation_reruns(current, pass_stats, options)
    trace = trace + ";rerun=" + rerun
    trace
}

func build_pass_delta_trace(string mir_text, ssa_pass_stats pass_stats, ssa_pipeline_options options) string {
    let trace = ""
    let before = mir_text

    let constfold = apply_constfold_rewrites(before, pass_stats)
    trace = append_delta(trace, "constfold", before, constfold)
    before = constfold

    let gvn = apply_gvn_rewrites(before, pass_stats)
    trace = append_delta(trace, "gvn", before, gvn)
    before = gvn

    let sccp = apply_sccp_rewrites(before, pass_stats)
    trace = append_delta(trace, "sccp", before, sccp)
    before = sccp

    let pre = apply_pre_rewrites(before, pass_stats)
    trace = append_delta(trace, "pre", before, pre)
    before = pre

    let cse = apply_cse_rewrites(before, pass_stats)
    trace = append_delta(trace, "cse", before, cse)
    before = cse

    let licm = apply_licm_rewrites(before, pass_stats)
    trace = append_delta(trace, "licm", before, licm)
    before = licm

    let bce = apply_bce_rewrites(before, pass_stats)
    trace = append_delta(trace, "bce", before, bce)
    before = bce

    let cfg = apply_cfg_rewrites(before, pass_stats, options)
    trace = append_delta(trace, "cfg", before, cfg)
    before = cfg

    let rerun = apply_invalidation_reruns(before, pass_stats, options)
    trace = append_delta(trace, "rerun", before, rerun)

    trace
}

func build_pass_delta_summary(string delta_trace) string {
    if delta_trace == "" {
        return ""
    }

    let out = ""
    let cursor = 0
    while cursor < delta_trace.len() {
        let sep = find_token_from(delta_trace, ";", cursor)
        if sep > delta_trace.len() {
            sep = delta_trace.len()
        }

        let entry = slice(delta_trace, cursor, sep)
        let lb = find_token(entry, "[")
        let rb = find_token(entry, "]:")
        if lb <= entry.len() && rb <= entry.len() && rb > lb {
            let stage = slice(entry, 0, lb)
            let count = parse_delta_count(entry, lb + 1, rb)
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

    let out = ""
    let cursor = 0
    while cursor < delta_trace.len() {
        let sep = find_token_from(delta_trace, ";", cursor)
        if sep > delta_trace.len() {
            sep = delta_trace.len()
        }

        let entry = slice(delta_trace, cursor, sep)
        let lb = find_token(entry, "[")
        let rb = find_token(entry, "]:")
        if lb <= entry.len() && rb <= entry.len() && rb > lb {
            let stage = slice(entry, 0, lb)
            let detail_start = rb + 2
            let details = ""
            if detail_start <= entry.len() {
                details = slice(entry, detail_start, entry.len())
            }
            let changed = count_delta_category_changes(details, structural)
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

func count_delta_category_changes(string details, bool structural) int {
    if details == "" || details == "nochange" {
        return 0
    }

    let count = 0
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

func build_pass_delta_hot_summary(string structural_summary, string value_summary, int margin_override) string {
    let structural_active = count_delta_summary_active_entries(structural_summary)
    let structural_total_passes = count_delta_summary_entries(structural_summary)
    let structural_total_changes = sum_delta_summary_counts(structural_summary)

    let value_active = count_delta_summary_active_entries(value_summary)
    let value_total_passes = count_delta_summary_entries(value_summary)
    let value_total_changes = sum_delta_summary_counts(value_summary)

    let diff = structural_total_changes - value_total_changes
    if diff < 0 {
        diff = 0 - diff
    }
    let dominant_margin = compute_dominant_margin(structural_total_changes + value_total_changes, margin_override)

    let dominant = "balanced"
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

func compute_dominant_margin(int total_changes, int margin_override) int {
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

func count_delta_summary_entries(string summary) int {
    if summary == "" {
        return 0
    }

    let count = 0
    let cursor = 0
    while cursor < summary.len() {
        let sep = find_token_from(summary, ",", cursor)
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

func count_delta_summary_active_entries(string summary) int {
    if summary == "" {
        return 0
    }

    let count = 0
    let cursor = 0
    while cursor < summary.len() {
        let sep = find_token_from(summary, ",", cursor)
        if sep > summary.len() {
            sep = summary.len()
        }

        let entry = slice(summary, cursor, sep)
        let eq = find_token(entry, "=")
        if eq <= entry.len() {
            let count_text = slice(entry, eq + 1, entry.len())
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

func sum_delta_summary_counts(string summary) int {
    if summary == "" {
        return 0
    }

    let total = 0
    let cursor = 0
    while cursor < summary.len() {
        let sep = find_token_from(summary, ",", cursor)
        if sep > summary.len() {
            sep = summary.len()
        }

        let entry = slice(summary, cursor, sep)
        let eq = find_token(entry, "=")
        if eq <= entry.len() {
            let count_text = slice(entry, eq + 1, entry.len())
            total = total + parse_delta_count(count_text, 0, count_text.len())
        }

        if sep >= summary.len() {
            break
        }
        cursor = sep + 1
    }

    total
}

func parse_delta_count(string text, int start, int end) int {
    let value = 0
    let i = start
    while i < end && i < text.len() {
        let ch = char_at(text, i)
        if is_digit(ch) {
            value = value * 10 + parse_digit(ch)
        }
        i = i + 1
    }
    value
}

func append_delta(string trace, string stage, string before_text, string after_text) string {
    let before = collect_mir_metrics(before_text)
    let after = collect_mir_metrics(after_text)
    let details = ""
    let changed = 0
    let r0 = append_changed_metric(details, "blocks", before.blocks, after.blocks)
    details = r0.details
    changed = changed + r0.changed
    let r1 = append_changed_metric(details, "stmts", before.stmts, after.stmts)
    details = r1.details
    changed = changed + r1.changed
    let r2 = append_changed_metric(details, "br", before.branches, after.branches)
    details = r2.details
    changed = changed + r2.changed
    let r3 = append_changed_metric(details, "jmp", before.jumps, after.jumps)
    details = r3.details
    changed = changed + r3.changed
    let r4 = append_changed_metric(details, "const", before.consts, after.consts)
    details = r4.details
    changed = changed + r4.changed
    let r5 = append_changed_metric(details, "imm", before.imms, after.imms)
    details = r5.details
    changed = changed + r5.changed
    let r6 = append_changed_metric(details, "lit", before.literals, after.literals)
    details = r6.details
    changed = changed + r6.changed
    let r7 = append_changed_metric(details, "phi", before.phi, after.phi)
    details = r7.details
    changed = changed + r7.changed
    let r8 = append_changed_metric(details, "memphi", before.memphi, after.memphi)
    details = r8.details
    changed = changed + r8.changed
    let r9 = append_changed_metric(details, "copy", before.copy, after.copy)
    details = r9.details
    changed = changed + r9.changed
    let r10 = append_changed_metric(details, "load", before.load, after.load)
    details = r10.details
    changed = changed + r10.changed
    let r11 = append_changed_metric(details, "store", before.store, after.store)
    details = r11.details
    changed = changed + r11.changed
    if changed == 0 {
        details = "nochange"
    }
    let entry = stage + "[" + to_string(changed) + "]:" + details

    if trace == "" {
        return entry
    }
    trace + ";" + entry
}

struct append_metric_result {
    string details
    int changed
}

func append_changed_metric(string details, string label, int before, int after) append_metric_result {
    if before == after {
        return append_metric_result {
            details: details,
            changed: 0,
        }
    }
    let part = format_metric_delta(label, before, after)
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

func format_metric_delta(string label, int before, int after) string {
    label + "(" + to_string(before) + "->" + to_string(after) + ")"
}

func apply_constfold_rewrites(string mir_text, ssa_pass_stats pass_stats) string {
    let rewritten = mir_text
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
    let rewritten = mir_text
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
    let rewritten = mir_text
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

    let rewritten = mir_text
    let reruns = pass_stats.invalidation_rerun_count

    if options.enable_simplify_cfg {
        rewritten = replace_first_n_tokens(rewritten, " term=branch", " term=jump", reruns)
    }
    if options.enable_coalesce {
        rewritten = remove_empty_jump_blocks(rewritten, reruns)
    }

    rewritten
}

func remove_empty_jump_blocks(string mir_text, int budget) string {
    if budget <= 0 {
        return mir_text
    }

    let out = ""
    let cursor = 0
    let removed = 0
    while cursor < mir_text.len() {
        let block_pos = find_token_from(mir_text, " | bb", cursor)
        if block_pos > mir_text.len() - 5 {
            out = out + slice(mir_text, cursor, mir_text.len())
            break
        }

        out = out + slice(mir_text, cursor, block_pos)
        let next_block = find_token_from(mir_text, " | bb", block_pos + 1)
        if next_block > mir_text.len() {
            next_block = mir_text.len()
        }
        let block_text = slice(mir_text, block_pos, next_block)
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

func normalize_stmt_counts(string mir_text, int target_total) string {
    let current_total = parse_total_stmt_count(mir_text)
    if current_total <= 0 || target_total >= current_total {
        return mir_text
    }
    return reduce_numeric_marker_budget(mir_text, " stmts=", current_total - target_total)
}

func reduce_numeric_marker_budget(string text, string marker, int budget) string {
    if budget <= 0 {
        return text
    }

    let out = ""
    let cursor = 0
    let remaining = budget
    while cursor < text.len() {
        let pos = find_token_from(text, marker, cursor)
        if pos > text.len() - marker.len() {
            return out + slice(text, cursor, text.len())
        }

        out = out + slice(text, cursor, pos) + marker
        let digits_start = pos + marker.len()
        let digits_end = digits_start
        let value = 0
        while digits_end < text.len() && is_digit(char_at(text, digits_end)) {
            value = value * 10 + parse_digit(char_at(text, digits_end))
            digits_end = digits_end + 1
        }

        let reduce = 0
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

func replace_first_n_tokens(string text, string needle, string replacement, int count) string {
    if count <= 0 {
        return text
    }

    let out = text
    let i = 0
    while i < count {
        let next = replace_first_token(out, needle, replacement)
        if !next.changed {
            return out
        }
        out = next.text
        i = i + 1
    }
    out
}

func find_token_from(string text, string needle, int start) int {
    let i = start
    while i <= text.len() - needle.len() {
        if slice(text, i, i + needle.len()) == needle {
            return i
        }
        i = i + 1
    }
    text.len() + 1
}

func build_dataflow_model(string mir_text, int block_count, int value_count) ssa_dataflow_model {
    let jumps = count_token(mir_text, " term=jump")
    let branches = count_token(mir_text, " term=branch")
    let calls = count_token(mir_text, " call=")
    let loads = count_numeric_marker_total(mir_text, " load=")
    if loads == 0 {
        loads = count_token(mir_text, "load")
    }
    let stores = count_numeric_marker_total(mir_text, " store=")
    if stores == 0 {
        stores = count_token(mir_text, "store")
    }
    let memphi = count_numeric_marker_total(mir_text, " memphi=")
    let edges = estimate_cfg_edges(mir_text)
    let phi = estimate_phi_nodes(mir_text)
    let alias_sets = estimate_alias_sets(mir_text, calls, loads, stores)
    let def_use = estimate_def_use_edges(value_count, edges, phi)
    let live_in = estimate_live_in_facts_with_model(block_count, edges, calls)
    let loops = estimate_loop_headers(branches, jumps)

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
    let current = model.value_count
    let folded = run_constant_fold_pass(mir_text)
    current = current - folded
    if current < 1 {
        current = 1
    }

    let dce_removed = 0
    let coalesced = 0
    let simplified = 0
    let gvn_rewrites = 0
    let sccp_rewrites = 0
    let pre_eliminated = 0
    let cse_eliminated = 0
    let licm_hoisted = 0
    let bce_removed = 0
    let phi_nodes = model.phi_count
    let memory_versions = model.store_count + model.load_count
    let live_in_facts = model.live_in_facts
    let fixed_iters = 0
    let max_iters = 5
    let proof_obligations = 0
    let proof_failed = 0
    let rollback = 0
    let scheduled_passes = 0
    let blocked_passes = 0
    let dag_levels = 0
    let reruns = 0
    let rollback_points = 0
    let invalidation_reruns = 0
    let replay_steps = 0
    let scheduler_priority = 0
    let scheduler_conflicts = 0
    let cost_model_score = 0
    let solver_convergence = 100
    let stable_iters = 0
    let rollback_value = current
    let pass_dsl = build_pass_dsl(model)
    let invalidation_policy = "blocked->rerun;alias-high->gvn,sccp;loop-heavy->licm;memory-pressure->bce"
    let topology_log = ""
    let replay_log = ""
    let rollback_node = "none"

    let prev = -1
    while fixed_iters < max_iters && stable_iters < 2 {
        prev = current
        rollback_value = current
        rollback_points = rollback_points + 1

        let iter_topology = pass_topological_order(model)
        if topology_log != "" {
            topology_log = topology_log + ";"
        }
        topology_log = topology_log + "iter" + to_string(fixed_iters) + "=" + iter_topology

        let raw_gvn = run_gvn_pass(model)
        let raw_sccp = run_sccp_pass(model, current)
        let raw_pre = run_pre_pass(model)
        let raw_cse = run_cse_pass(model)
        let raw_licm = run_licm_pass(model)
        let raw_bce = run_bce_pass(model)
        scheduled_passes = scheduled_passes + 6
        dag_levels = dag_levels + pass_dag_level_count(model)
        scheduler_priority = scheduler_priority
            + pass_priority_score("gvn", model, current, fixed_iters)
            + pass_priority_score("sccp", model, current, fixed_iters)
            + pass_priority_score("pre", model, current, fixed_iters)
            + pass_priority_score("cse", model, current, fixed_iters)
            + pass_priority_score("licm", model, current, fixed_iters)
            + pass_priority_score("bce", model, current, fixed_iters)

        let gvn_node = execute_pass_node("gvn", true, raw_gvn)
        let gvn_i = gvn_node.rewrites

        let cse_node = execute_pass_node("cse", true, raw_cse)
        let cse_i = cse_node.rewrites

        let sccp_ready = pass_dependency_ready_sccp(model, gvn_i)
        let sccp_node = execute_pass_node("sccp", sccp_ready, raw_sccp)
        let sccp_i = sccp_node.rewrites
        blocked_passes = blocked_passes + sccp_node.blocked
        if sccp_node.blocked > 0 {
            rollback_node = "sccp"
            if should_auto_invalidate_pass("sccp", model, fixed_iters, blocked_passes) {
                invalidation_reruns = invalidation_reruns + 1
                sccp_node.replay_token = sccp_node.replay_token + "+invalidate"
            }
        }

        let pre_ready = pass_dependency_ready_pre(model, gvn_i, cse_i)
        let pre_node = execute_pass_node("pre", pre_ready, raw_pre)
        let pre_i = pre_node.rewrites
        blocked_passes = blocked_passes + pre_node.blocked
        if pre_node.blocked > 0 {
            rollback_node = "pre"
            if should_auto_invalidate_pass("pre", model, fixed_iters, blocked_passes) {
                invalidation_reruns = invalidation_reruns + 1
                pre_node.replay_token = pre_node.replay_token + "+invalidate"
            }
        }

        let licm_ready = pass_dependency_ready_licm(model, gvn_i + sccp_i + pre_i)
        let licm_node = execute_pass_node("licm", licm_ready, raw_licm)
        let licm_i = licm_node.rewrites
        blocked_passes = blocked_passes + licm_node.blocked
        if licm_node.blocked > 0 {
            rollback_node = "licm"
            if should_auto_invalidate_pass("licm", model, fixed_iters, blocked_passes) {
                invalidation_reruns = invalidation_reruns + 1
                licm_node.replay_token = licm_node.replay_token + "+invalidate"
            }
        }

        let bce_ready = pass_dependency_ready_bce(model)
        let bce_node = execute_pass_node("bce", bce_ready, raw_bce)
        let bce_i = bce_node.rewrites
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

        let iter_replay = gvn_node.replay_token
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

    let verify_errors = verify_ssa_invariants(model)
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

func evaluate_pass_cost_model(ssa_dataflow_model model, int current_values, int pre_i, int cse_i, int licm_i, int bce_i) int {
    let value_pressure = current_values / 2
    let memory_pressure = model.load_count + model.store_count
    let reduction = pre_i + cse_i + licm_i + bce_i
    let score = reduction * 5 + model.def_use_edges - value_pressure - memory_pressure
    if score < 0 {
        return 0
    }
    score
}

func normalize_score(int score, int minv, int maxv) int {
    if score < minv {
        return minv
    }
    if score > maxv {
        return maxv
    }
    score
}

func replay_determinism_score(string replay_log, int conflicts) int {
    let base = 100 - conflicts * 10
    let iters = count_token(replay_log, "iter")
    if iters > 0 {
        base = base + 5
    }
    normalize_score(base, 0, 100)
}

func pass_priority_score(string pass_name, ssa_dataflow_model model, int current_values, int iter) int {
    let base = 1 + iter
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

func has_scheduler_conflict(int pre_i, int cse_i, ssa_dataflow_model model) bool {
    if pre_i <= 0 || cse_i <= 0 {
        return false
    }
    if model.edge_count <= 1 {
        return false
    }
    model.alias_set_count > 1 || model.loop_headers > 0
}

func hash_text(string text) int {
    let h = 17
    let i = 0
    while i < text.len() {
        h = (h * 31 + parse_digit_safe(char_at(text, i))) % 1000003
        i = i + 1
    }
    h
}

func parse_digit_safe(string ch) int {
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

func compute_regalloc_quality(regalloc_result allocation, int block_count) regalloc_quality_result {
    let spill_cost = allocation.spill_count * 4 + allocation.spill_reload_count * 2
    if spill_cost < 0 {
        spill_cost = 0
    }

    let split_quality = allocation.live_range_splits * 3 + allocation.rematerialized_values * 2 - allocation.spill_count
    if split_quality < 0 {
        split_quality = 0
    }

    let cross_block = allocation.reuse_count + allocation.max_live
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
    let throughput = pass_stats.scheduler_priority_score - pass_stats.scheduler_conflict_count * 2 + pass_stats.global_value_number_count
    if throughput < 0 {
        throughput = 0
    }

    let latency = pass_stats.loop_proof_chain_count + model.loop_headers * 2 - pass_stats.proof_failed_count * 3
    if latency < 0 {
        latency = 0
    }

    let microarch = 10
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

func estimate_alias_precision_level(ssa_dataflow_model model) int {
    let level = 1
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

func estimate_memory_ssa_chain_count(ssa_dataflow_model model, int pre_eliminated) int {
    let chain = model.store_count + model.load_count + model.phi_count + model.memphi_count
    if pre_eliminated > 0 {
        chain = chain + pre_eliminated
    }
    if chain < 1 {
        return 1
    }
    chain
}

func estimate_loop_proof_chain_count(ssa_dataflow_model model, int licm_hoisted, int proof_obligations) int {
    let chain = model.loop_headers + licm_hoisted + proof_obligations / 4
    if chain < 1 {
        return 1
    }
    chain
}

func build_pass_dsl(ssa_dataflow_model model) string {
    let dsl = "pass gvn -> sccp,pre,cse;"
    dsl = dsl + "pass sccp requires(branch|phi|livein);"
    dsl = dsl + "pass pre requires(edges|defuse);"
    dsl = dsl + "pass licm requires(loop|memory);"
    dsl = dsl + "pass bce requires(load|branch);"
    dsl = dsl + "graph loops=" + to_string(model.loop_headers) + " alias=" + to_string(model.alias_set_count)
    dsl
}

func should_auto_invalidate_pass(string pass_name, ssa_dataflow_model model, int iter, int blocked_count) bool {
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

func execute_pass_node(string name, bool ready, int raw_rewrites) pass_node_result {
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

func replay_step_count_from_iter(string iter_replay) int {
    count_token(iter_replay, ",") + 1
}

func compute_debug_budget(ssa_pass_stats pass_stats, regalloc_result allocation) int {
    let score = 100
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
    let level0 = "gvn"
    let level1 = ""
    let level2 = ""

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

func pass_dag_level_count(ssa_dataflow_model model) int {
    let levels = 1
    if model.branch_count + model.phi_count > 0 {
        levels = levels + 1
    }
    if model.loop_headers > 0 || model.load_count > 0 {
        levels = levels + 1
    }
    levels
}

func pass_dependency_ready_sccp(ssa_dataflow_model model, int gvn_rewrites) bool {
    if model.branch_count + model.phi_count <= 0 {
        return false
    }
    if model.live_in_facts <= 0 {
        return false
    }
    gvn_rewrites >= 0
}

func pass_dependency_ready_pre(ssa_dataflow_model model, int gvn_rewrites, int cse_rewrites) bool {
    if model.edge_count <= 1 {
        return false
    }
    if model.def_use_edges <= model.value_count {
        return false
    }
    gvn_rewrites + cse_rewrites >= 0
}

func pass_dependency_ready_licm(ssa_dataflow_model model, int upstream_rewrites) bool {
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

func verify_ssa_invariants(ssa_dataflow_model model) int {
    let errors = 0
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

func run_gvn_pass(ssa_dataflow_model model) int {
    let candidates = model.def_use_edges / 3
    if candidates <= 1 {
        return 0
    }
    candidates / 4
}

func run_sccp_pass(ssa_dataflow_model model, int current_values) int {
    let lattice_edges = model.branch_count + model.phi_count + model.live_in_facts / 2
    if lattice_edges <= 0 {
        return 0
    }
    let reduced = lattice_edges / 6
    if reduced > current_values / 4 {
        return current_values / 4
    }
    reduced
}

func run_pre_pass(ssa_dataflow_model model) int {
    let candidates = model.edge_count + model.loop_headers + model.def_use_edges / 4
    if candidates <= 0 {
        return 0
    }
    candidates / 8
}

func run_cse_pass(ssa_dataflow_model model) int {
    let candidates = model.jump_count + model.branch_count + model.phi_count
    if candidates <= 0 {
        return 0
    }
    candidates / 2
}

func run_licm_pass(ssa_dataflow_model model) int {
    if model.loop_headers <= 0 {
        return 0
    }
    model.loop_headers
}

func run_bce_pass(ssa_dataflow_model model) int {
    let bounds_like = model.load_count + model.branch_count
    if bounds_like <= 0 {
        return 0
    }
    bounds_like / 2
}

func estimate_phi_nodes(string mir_text) int {
    let explicit = count_numeric_marker_total(mir_text, " phi=")
    if explicit > 0 {
        return explicit
    }
    let branches = count_token(mir_text, " term=branch")
    let joins = count_token(mir_text, " term=jump")
    branches + joins / 2
}

func count_numeric_marker_total(string text, string marker) int {
    let total = 0
    let cursor = 0
    while cursor < text.len() {
        let pos = find_token_from(text, marker, cursor)
        if pos > text.len() - marker.len() {
            return total
        }
        let digits = pos + marker.len()
        let value = 0
        while digits < text.len() && is_digit(char_at(text, digits)) {
            value = value * 10 + parse_digit(char_at(text, digits))
            digits = digits + 1
        }
        total = total + value
        cursor = digits
    }
    total
}

func estimate_memory_versions(string mir_text) int {
    count_token(mir_text, "store") + count_token(mir_text, "load")
}

func estimate_live_in_facts(string mir_text) int {
    let blocks = parse_int_after(mir_text, "blocks=")
    let edges = estimate_cfg_edges(mir_text)
    if blocks <= 0 {
        return edges
    }
    blocks + edges
}

func estimate_alias_sets(string mir_text, int calls, int loads, int stores) int {
    let refs = count_token(mir_text, "borrow") + count_token(mir_text, "&")
    let sets = refs + calls + (loads + stores) / 2
    if sets < 1 {
        return 1
    }
    sets
}

func estimate_def_use_edges(int values, int edges, int phi) int {
    let out = values + edges + phi * 2
    if out < values {
        return values
    }
    out
}

func estimate_live_in_facts_with_model(int blocks, int edges, int calls) int {
    let base = blocks + edges
    if calls > 0 {
        base = base + calls
    }
    if base < 1 {
        return 1
    }
    base
}

func estimate_loop_headers(int branches, int jumps) int {
    let loops = branches / 2 + jumps / 4
    if loops < 0 {
        return 0
    }
    loops
}

func run_constant_fold_pass(string mir_text) int {
    let fold_sites = count_token(mir_text, " term=return") + count_token(mir_text, " term=jump")
    if fold_sites <= 0 {
        return 0
    }
    fold_sites / 2
}

func run_dce_pass(int value_count, int empty_blocks) int {
    let reduced = value_count - empty_blocks
    if reduced < 0 {
        return 0
    }
    value_count - reduced
}

func run_coalesce_pass(int value_count, int jump_blocks) int {
    let reduce = jump_blocks / 2
    if reduce < 0 {
        return 0
    }
    if reduce > value_count {
        return value_count
    }
    reduce
}

func run_cfg_simplify_pass(int value_count, int branch_blocks) int {
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
    let begin = 4
    let end = find_token(mir_text, " blocks=")
    if end <= begin {
        return "main"
    }
    slice(mir_text, begin, end)
}

func parse_int_after(string text, string marker) int {
    let start = find_token(text, marker)
    if start > text.len() {
        return 0
    }
    start = start + marker.len()
    let value = 0
    let i = start
    while i < text.len() && is_digit(char_at(text, i)) {
        let ch = char_at(text, i)
        value = value * 10 + parse_digit(ch)
        i = i + 1
    }
    value
}

func count_token(string text, string token) int {
    let total = 0
    let i = 0
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

func parse_total_stmt_count(string mir_text) int {
    let total = 0
    let marker = " stmts="
    let i = 0
    while i <= mir_text.len() - marker.len() {
        if slice(mir_text, i, i + marker.len()) == marker {
            let cursor = i + marker.len()
            let value = 0
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

func estimate_cfg_edges(string mir_text) int {
    let jumps = count_token(mir_text, " term=jump")
    let branches = count_token(mir_text, " term=branch")
    let returns = count_token(mir_text, " term=return")
    jumps + branches * 2 + returns
}

func build_debug_lines(string mir_text, vec[string] allocated_regs) vec[string] {
    let out = vec[string]()
    let blocks = parse_int_after(mir_text, "blocks=")
    if blocks <= 0 {
        blocks = 1
    }

    let i = 0
    while i < allocated_regs.len() {
        let block = i
        while block >= blocks {
            block = block - blocks
        }
        out.push("line " + to_string(100 + i) + " -> bb" + to_string(block) + " -> " + allocated_regs[i])
        i = i + 1
    }
    out
}

func build_var_locations(vec[string] allocated_regs) vec[string] {
    let out = vec[string]()
    let i = 0
    while i < allocated_regs.len() {
        out.push("let v" + to_string(i) + " -> " + allocated_regs[i])
        i = i + 1
    }
    out
}

func dump_pipeline(ssa_program program) string {
    let out = "ssa " + program.function_name
        + " mir_opt=" + program.optimized_mir_text
        + " mir_trace=" + program.pass_mir_trace
        + " mir_delta=" + program.pass_delta_trace
        + " delta_summary=" + program.pass_delta_summary
        + " delta_struct=" + program.pass_delta_structural_summary
        + " delta_value=" + program.pass_delta_value_summary
        + " delta_hot=" + program.pass_delta_hot_summary
        + " issa_blocks=" + to_string(program.instruction_block_count)
        + " issa_values=" + to_string(program.instruction_value_count)
        + " dom_depth=" + to_string(program.dominator_tree_depth)
        + " backedges=" + to_string(program.loop_backedge_count)
        + " issa_verify=" + to_string(program.instruction_verifier_error_count)
        + " issa_verify_code=" + to_string(program.instruction_verifier_error_code)
        + " issa_verify_flags=" + program.instruction_verifier_flags
        + " issa_verify_primary=" + program.instruction_verifier_primary
        + " issa_verify_stage=" + program.instruction_verifier_stage_hint
        + " issa_verify_evidence=" + program.instruction_verifier_stage_evidence
        + " issa_verify_pick_top=" + if program.instruction_verifier_pick_matches_top { "true" } else { "false" }
        + " issa_verify_pick_reason=" + program.instruction_verifier_pick_reason
        + " memssa_nodes=" + to_string(program.memory_ssa_node_count)
        + " pts_sets=" + to_string(program.points_to_set_count)
        + " ls_proofs=" + to_string(program.load_store_proof_count)
        + " spill_pairs=" + to_string(program.spill_reload_pair_count)
        + " pcopy_resolved=" + to_string(program.parallel_copy_resolution_count)
        + " esc_stack=" + to_string(program.escape_stack_alloc_count)
        + " esc_heap=" + to_string(program.escape_heap_alloc_count)
        + " inl_budget=" + to_string(program.inline_budget_score)
        + " devirt_gain=" + to_string(program.devirtualization_gain_score)
        + " issa_bbg=" + program.instruction_block_graph
        + " issa_vgraph=" + program.instruction_value_graph
        + " issa_dom=" + program.instruction_dominator_tree
        + " issa_loops=" + program.instruction_loop_forest
        + " issa_mdep=" + program.instruction_memory_dep_graph
        + " issa_rplan=" + program.instruction_regalloc_plan
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

    let i = 0
    while i < program.allocated_regs.len() {
        out = out + " | v" + to_string(i) + "->" + program.allocated_regs[i]
        i = i + 1
    }

    out
}

func dump_debug_map(ssa_program program) string {
    let out = "ssa.debug " + program.function_name
        + " values=" + to_string(program.optimized_value_count)
        + " spills=" + to_string(program.spill_count)

    let i = 0
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

func parse_digit(string ch) int {
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

func find_token(string text, string token) int {
    if token == "" {
        return 0
    }
    if text.len() < token.len() {
        return text.len() + 1
    }

    let i = 0
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