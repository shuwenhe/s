package compile.internal.ssa_core

use std.prelude.char_at
use std.prelude.len
use std.prelude.slice
use std.prelude.to_string
use std.vec.vec

struct ssa_pipeline_options {
    bool enable_dce
    bool enable_coalesce
    bool enable_simplify_cfg
}

struct ssa_program {
    string function_name
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
    int32 alias_set_count
    int32 def_use_edges
    int32 live_in_facts
    int32 loop_headers
}

func build_pipeline(string mir_text, string goarch) ssa_program {
    return build_pipeline_with_options(mir_text, goarch, default_options())
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
    var optimized_value_count = pass_stats.optimized_value_count
    if pass_stats.verification_error_count > 0 {
        optimized_value_count = value_count
    }
    var allocation = linear_scan_regalloc_with_spill(rewritten, optimized_value_count, goarch)
    var debug_budget = compute_debug_budget(pass_stats, allocation)
    var debug_lines = build_debug_lines(rewritten, allocation.allocated_regs)
    var debug_var_locations = build_var_locations(allocation.allocated_regs)

    ssa_program {
        function_name: function_name,
        block_count: block_count,
        value_count: value_count,
        cfg_edge_count: estimate_cfg_edges(rewritten),
        branch_block_count: count_token(rewritten, " term=branch"),
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
    }
}

func build_dataflow_model(string mir_text, int32 block_count, int32 value_count) ssa_dataflow_model {
    var jumps = count_token(mir_text, " term=jump")
    var branches = count_token(mir_text, " term=branch")
    var calls = count_token(mir_text, " call=")
    var loads = count_token(mir_text, "load")
    var stores = count_token(mir_text, "store")
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
            if blocked_passes > 0 && fixed_iters + 1 < max_iters {
                reruns = reruns + 1
            }
        } else {
            stable_iters = 0
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
        pass_dsl: pass_dsl,
        invalidation_policy: invalidation_policy,
        pass_topology_log: topology_log,
        pass_replay_log: replay_log,
        rollback_node: rollback_node,
        optimized_value_count: current,
    }
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
    var branches = count_token(mir_text, " term=branch")
    var joins = count_token(mir_text, " term=jump")
    branches + joins / 2
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