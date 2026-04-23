package compile.internal.ssa_core

use std.prelude.char_at
use std.prelude.len
use std.prelude.slice
use std.prelude.to_string
use std.vec.vec

struct ssa_pipeline_options {
    bool enable_dce,
    bool enable_coalesce,
    bool enable_simplify_cfg,
}

struct ssa_program {
    string function_name,
    int32 block_count,
    int32 value_count,
    int32 cfg_edge_count,
    int32 branch_block_count,
    int32 optimized_value_count,
    int32 folded_constant_count,
    int32 dce_removed_count,
    int32 coalesced_move_count,
    int32 simplified_branch_count,
    int32 gvn_rewrite_count,
    int32 cse_eliminated_count,
    int32 licm_hoisted_count,
    int32 bce_removed_count,
    int32 phi_node_count,
    int32 memory_version_count,
    int32 live_in_fact_count,
    int32 spill_count,
    int32 spill_reload_count,
    int32 call_pressure_event_count,
    int32 regalloc_reuse_count,
    int32 regalloc_max_live,
    int32 debug_line_count,
    vec[string] allocated_regs,
    vec[string] debug_lines,
    vec[string] debug_var_locations,
}

struct ssa_pass_stats {
    int32 folded_constant_count,
    int32 dce_removed_count,
    int32 coalesced_move_count,
    int32 simplified_branch_count,
    int32 gvn_rewrite_count,
    int32 cse_eliminated_count,
    int32 licm_hoisted_count,
    int32 bce_removed_count,
    int32 phi_node_count,
    int32 memory_version_count,
    int32 live_in_fact_count,
    int32 optimized_value_count,
}

func build_pipeline(string mir_text, string goarch) ssa_program {
    return build_pipeline_with_options(mir_text, goarch, default_options())
}

func build_pipeline_with_options(string mir_text, string goarch, ssa_pipeline_options options) ssa_program {
    var function_name = parse_function_name(mir_text)
    var block_count = parse_int_after(mir_text, "blocks=")
    var value_count = parse_total_stmt_count(mir_text)
    if value_count == 0 {
        value_count = block_count
    }
    var pass_stats = run_optimization_passes(mir_text, value_count, options)
    var optimized_value_count = pass_stats.optimized_value_count
    var allocation = linear_scan_regalloc_with_spill(mir_text, optimized_value_count, goarch)
    var debug_lines = build_debug_lines(mir_text, allocation.allocated_regs)
    var debug_var_locations = build_var_locations(allocation.allocated_regs)

    ssa_program {
        function_name: function_name,
        block_count: block_count,
        value_count: value_count,
        cfg_edge_count: estimate_cfg_edges(mir_text),
        branch_block_count: count_token(mir_text, " term=branch"),
        optimized_value_count: optimized_value_count,
        folded_constant_count: pass_stats.folded_constant_count,
        dce_removed_count: pass_stats.dce_removed_count,
        coalesced_move_count: pass_stats.coalesced_move_count,
        simplified_branch_count: pass_stats.simplified_branch_count,
        gvn_rewrite_count: pass_stats.gvn_rewrite_count,
        cse_eliminated_count: pass_stats.cse_eliminated_count,
        licm_hoisted_count: pass_stats.licm_hoisted_count,
        bce_removed_count: pass_stats.bce_removed_count,
        phi_node_count: pass_stats.phi_node_count,
        memory_version_count: pass_stats.memory_version_count,
        live_in_fact_count: pass_stats.live_in_fact_count,
        spill_count: allocation.spill_count,
        spill_reload_count: allocation.spill_reload_count,
        call_pressure_event_count: allocation.call_pressure_events,
        regalloc_reuse_count: allocation.reuse_count,
        regalloc_max_live: allocation.max_live,
        debug_line_count: debug_lines.len(),
        allocated_regs: allocation.allocated_regs,
        debug_lines: debug_lines,
        debug_var_locations: debug_var_locations,
    }
}

struct regalloc_result {
    vec[string] allocated_regs,
    int32 spill_count,
    int32 spill_reload_count,
    int32 call_pressure_events,
    int32 reuse_count,
    int32 max_live,
}

func linear_scan_regalloc_with_spill(string mir_text, int32 value_count, string goarch) regalloc_result {
    var regs = register_bank(goarch)
    var call_sites = count_token(mir_text, " call=")
    if regs.len() == 0 {
        return regalloc_result {
            allocated_regs: vec[string](),
            spill_count: value_count,
            spill_reload_count: value_count,
            call_pressure_events: call_sites,
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
    var reuse = 0
    var max_live = 0
    var live_width = 3
    if call_sites > 0 {
        // Calls shorten allocatable windows and increase spill/reload pressure.
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
            active_until[chosen] = i + live_width
            out.push(regs[chosen])

            var live_now = count_live_regs(active_until, i)
            if live_now > max_live {
                max_live = live_now
            }
        } else {
            out.push("spill(" + to_string(i - regs.len()) + ")")
            spills = spills + 1
            spill_reloads = spill_reloads + 1
        }
        i = i + 1
    }

    regalloc_result {
        allocated_regs: out,
        spill_count: spills,
        spill_reload_count: spill_reloads,
        call_pressure_events: call_sites,
        reuse_count: reuse,
        max_live: max_live,
    }
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

func run_optimization_passes(string mir_text, int32 value_count, ssa_pipeline_options options) ssa_pass_stats {
    var current = value_count
    var folded = run_constant_fold_pass(mir_text)
    current = current - folded
    if current < 1 {
        current = 1
    }

    var dce_removed = 0
    var coalesced = 0
    var simplified = 0
    var gvn_rewrites = run_gvn_pass(mir_text)
    current = current - gvn_rewrites
    if current < 1 {
        current = 1
    }
    var cse_eliminated = run_cse_pass(mir_text)
    current = current - cse_eliminated
    if current < 1 {
        current = 1
    }
    var licm_hoisted = run_licm_pass(mir_text)
    var bce_removed = run_bce_pass(mir_text)
    var phi_nodes = estimate_phi_nodes(mir_text)
    var memory_versions = estimate_memory_versions(mir_text)
    var live_in_facts = estimate_live_in_facts(mir_text)

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
        cse_eliminated_count: cse_eliminated,
        licm_hoisted_count: licm_hoisted,
        bce_removed_count: bce_removed,
        phi_node_count: phi_nodes,
        memory_version_count: memory_versions,
        live_in_fact_count: live_in_facts,
        optimized_value_count: current,
    }
}

func run_gvn_pass(string mir_text) int32 {
    var candidates = count_token(mir_text, " stmts=")
    if candidates <= 1 {
        return 0
    }
    candidates / 6
}

func run_cse_pass(string mir_text) int32 {
    var candidates = count_token(mir_text, " term=jump") + count_token(mir_text, " term=branch")
    if candidates <= 0 {
        return 0
    }
    candidates / 2
}

func run_licm_pass(string mir_text) int32 {
    var branches = count_token(mir_text, " term=branch")
    if branches <= 0 {
        return 0
    }
    branches
}

func run_bce_pass(string mir_text) int32 {
    var bounds_like = count_token(mir_text, "index") + count_token(mir_text, "bounds")
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
        + " cse=" + to_string(program.cse_eliminated_count)
        + " licm=" + to_string(program.licm_hoisted_count)
        + " bce=" + to_string(program.bce_removed_count)
        + " phi=" + to_string(program.phi_node_count)
        + " memv=" + to_string(program.memory_version_count)
        + " livein=" + to_string(program.live_in_fact_count)
        + " cfg_edges=" + to_string(program.cfg_edge_count)
        + " branches=" + to_string(program.branch_block_count)
        + " spills=" + to_string(program.spill_count)
        + " reloads=" + to_string(program.spill_reload_count)
        + " call_pressure=" + to_string(program.call_pressure_event_count)
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