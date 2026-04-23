package compile.internal.tests.test_ssa

use compile.internal.ssa_core.build_pipeline
use compile.internal.ssa_core.dump_pipeline
use compile.internal.ssa_core.dump_debug_map
use std.prelude.slice

func run_ssa_suite() int32 {
    var mir_text = "mir main blocks=2 entry=0 exit=1 | bb0(entry) stmts=1 term=jump | bb1(exit) stmts=0 term=return"

    var arm64_dump = dump_pipeline(build_pipeline(mir_text, "arm64"))
    if !contains(arm64_dump, "blocks=2") {
        return 1
    }
    if !contains(arm64_dump, "opt_values=") {
        return 1
    }
    if !contains(arm64_dump, "folded=") {
        return 1
    }
    if !contains(arm64_dump, "dce=") {
        return 1
    }
    if !contains(arm64_dump, "v0->x9") {
        return 1
    }
    if !contains(arm64_dump, "cfg_edges=") {
        return 1
    }
    if !contains(arm64_dump, "reuse=") {
        return 1
    }
    if !contains(arm64_dump, "max_live=") {
        return 1
    }
    if !contains(arm64_dump, "gvn=") {
        return 1
    }
    if !contains(arm64_dump, "sccp=") {
        return 1
    }
    if !contains(arm64_dump, "pre=") {
        return 1
    }
    if !contains(arm64_dump, "cse=") {
        return 1
    }
    if !contains(arm64_dump, "licm=") {
        return 1
    }
    if !contains(arm64_dump, "phi=") {
        return 1
    }
    if !contains(arm64_dump, "livein=") {
        return 1
    }
    if !contains(arm64_dump, "defuse=") {
        return 1
    }
    if !contains(arm64_dump, "alias=") {
        return 1
    }
    if !contains(arm64_dump, "loops=") {
        return 1
    }
    if !contains(arm64_dump, "rewrites=") {
        return 1
    }
    if !contains(arm64_dump, "fix_iters=") {
        return 1
    }
    if !contains(arm64_dump, "verify_errs=") {
        return 1
    }
    if !contains(arm64_dump, "rollback=") {
        return 1
    }
    if !contains(arm64_dump, "proofs=") {
        return 1
    }
    if !contains(arm64_dump, "proof_fail=") {
        return 1
    }
    if !contains(arm64_dump, "passes_sched=") {
        return 1
    }
    if !contains(arm64_dump, "passes_blocked=") {
        return 1
    }
    if !contains(arm64_dump, "dag_levels=") {
        return 1
    }
    if !contains(arm64_dump, "reruns=") {
        return 1
    }
    if !contains(arm64_dump, "rollback_pts=") {
        return 1
    }
    if !contains(arm64_dump, "rollback_node=") {
        return 1
    }
    if !contains(arm64_dump, "pass_topo=") {
        return 1
    }
    if !contains(arm64_dump, "pass_replay=") {
        return 1
    }
    if !contains(arm64_dump, "replay_steps=") {
        return 1
    }
    if !contains(arm64_dump, "invalid_reruns=") {
        return 1
    }
    if !contains(arm64_dump, "dbg_budget=") {
        return 1
    }
    if !contains(arm64_dump, "pass_dsl=") {
        return 1
    }
    if !contains(arm64_dump, "inv_policy=") {
        return 1
    }
    if !contains(arm64_dump, "sched_prio=") {
        return 1
    }
    if !contains(arm64_dump, "sched_conflicts=") {
        return 1
    }
    if !contains(arm64_dump, "replay_hash=") {
        return 1
    }
    if !contains(arm64_dump, "alias_level=") {
        return 1
    }
    if !contains(arm64_dump, "memssa_chain=") {
        return 1
    }
    if !contains(arm64_dump, "gvn_total=") {
        return 1
    }
    if !contains(arm64_dump, "loop_proofs=") {
        return 1
    }
    if !contains(arm64_dump, "spill_cost=") {
        return 1
    }
    if !contains(arm64_dump, "split_quality=") {
        return 1
    }
    if !contains(arm64_dump, "cross_block_gain=") {
        return 1
    }
    if !contains(arm64_dump, "sched_tp=") {
        return 1
    }
    if !contains(arm64_dump, "sched_lat=") {
        return 1
    }
    if !contains(arm64_dump, "microarch=") {
        return 1
    }
    if !contains(arm64_dump, "cost_model=") {
        return 1
    }
    if !contains(arm64_dump, "solver_conv=") {
        return 1
    }
    if !contains(arm64_dump, "replay_det=") {
        return 1
    }

    var amd64_program = build_pipeline(mir_text, "amd64")
    var amd64_dump = dump_pipeline(amd64_program)
    if !contains(amd64_dump, "v0->r10") {
        return 1
    }
    var debug_map = dump_debug_map(amd64_program)
    if !contains(debug_map, "ssa.debug") {
        return 1
    }
    if !contains(debug_map, "value#0") {
        return 1
    }
    if !contains(debug_map, "line 100") {
        return 1
    }
    if !contains(debug_map, "var v0") {
        return 1
    }

    var heavy_mir = "mir heavy blocks=3 entry=0 exit=2 call=hot | bb0(entry) stmts=12 const=3 term=branch | bb1(mid) stmts=8 imm=2 term=jump | bb2(exit) stmts=0 literal=1 term=return"
    var heavy_dump = dump_pipeline(build_pipeline(heavy_mir, "amd64"))
    if !contains(heavy_dump, "spills=") {
        return 1
    }
    if !contains(heavy_dump, "reloads=") {
        return 1
    }
    if !contains(heavy_dump, "call_pressure=") {
        return 1
    }
    if !contains(heavy_dump, "splits=") {
        return 1
    }
    if !contains(heavy_dump, "remat=") {
        return 1
    }
    if !contains(heavy_dump, "spill(") {
        return 1
    }
    if !contains(heavy_dump, "split(v") {
        return 1
    }
    if !contains(heavy_dump, "remat(v") {
        return 1
    }
    if !contains(heavy_dump, "L0{") {
        return 1
    }
    if !contains(heavy_dump, "gvn:ok") {
        return 1
    }
    if !contains(heavy_dump, "invalidate") {
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