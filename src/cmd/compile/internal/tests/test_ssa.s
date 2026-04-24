package compile.internal.tests.test_ssa

use compile.internal.ssa_core.build_pipeline
use compile.internal.ssa_core.build_pipeline_with_margin
use compile.internal.ssa_core.dump_pipeline
use compile.internal.ssa_core.dump_debug_map
use std.prelude.slice

func run_ssa_suite() int {
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
    if !contains(arm64_dump, "mir_trace=input=") {
        return 1
    }
    if !contains(arm64_dump, ";constfold=mir main") {
        return 1
    }
    if !contains(arm64_dump, ";gvn=mir main") {
        return 1
    }
    if !contains(arm64_dump, ";sccp=mir main") {
        return 1
    }
    if !contains(arm64_dump, ";pre=mir main") {
        return 1
    }
    if !contains(arm64_dump, ";cse=mir main") {
        return 1
    }
    if !contains(arm64_dump, ";licm=mir main") {
        return 1
    }
    if !contains(arm64_dump, ";bce=mir main") {
        return 1
    }
    if !contains(arm64_dump, ";cfg=mir main") {
        return 1
    }
    if !contains(arm64_dump, ";rerun=mir main") {
        return 1
    }
    if !contains(arm64_dump, "mir_delta=constfold:") {
        return 1
    }
    if !contains(arm64_dump, ";gvn:") {
        return 1
    }
    if !contains(arm64_dump, ";cfg:") {
        return 1
    }
    if !contains(arm64_dump, ";rerun:") {
        return 1
    }
    if !contains(arm64_dump, ";rerun[0]:nochange") {
        return 1
    }
    if !contains(arm64_dump, "delta_summary=constfold=") {
        return 1
    }
    if !contains(arm64_dump, ",rerun=0") {
        return 1
    }
    if !contains(arm64_dump, "delta_struct=constfold=") {
        return 1
    }
    if !contains(arm64_dump, "delta_value=constfold=") {
        return 1
    }
    if !contains(arm64_dump, "delta_hot=struct=") {
        return 1
    }
    if !contains(arm64_dump, "),value=") {
        return 1
    }
    if !contains(arm64_dump, "/") {
        return 1
    }
    if !contains(arm64_dump, ",margin=") {
        return 1
    }
    if !contains(arm64_dump, ",dominant=") {
        return 1
    }
    if !contains(arm64_dump, "issa_blocks=") {
        return 1
    }
    if !contains(arm64_dump, "issa_values=") {
        return 1
    }
    if !contains(arm64_dump, "dom_depth=") {
        return 1
    }
    if !contains(arm64_dump, "backedges=") {
        return 1
    }
    if !contains(arm64_dump, "issa_verify=") {
        return 1
    }
    if !contains(arm64_dump, "issa_verify=0") {
        return 1
    }
    if !contains(arm64_dump, "issa_verify_code=0") {
        return 1
    }
    if !contains(arm64_dump, "issa_verify_flags=ok") {
        return 1
    }
    if !contains(arm64_dump, "issa_verify_primary=ok") {
        return 1
    }
    if !contains(arm64_dump, "issa_verify_stage=none") {
        return 1
    }
    if !contains(arm64_dump, "issa_verify_evidence=none") {
        return 1
    }
    if !contains(arm64_dump, "issa_verify_pick_top=true") {
        return 1
    }
    if !contains(arm64_dump, "issa_verify_pick_reason=ok") {
        return 1
    }
    if !contains(arm64_dump, "memssa_nodes=") {
        return 1
    }
    if !contains(arm64_dump, "pts_sets=") {
        return 1
    }
    if !contains(arm64_dump, "ls_proofs=") {
        return 1
    }
    if !contains(arm64_dump, "spill_pairs=") {
        return 1
    }
    if !contains(arm64_dump, "pcopy_resolved=") {
        return 1
    }
    if !contains(arm64_dump, "esc_stack=") {
        return 1
    }
    if !contains(arm64_dump, "esc_heap=") {
        return 1
    }
    if !contains(arm64_dump, "inl_budget=") {
        return 1
    }
    if !contains(arm64_dump, "devirt_gain=") {
        return 1
    }
    if !contains(arm64_dump, "issa_bbg=bbg(") {
        return 1
    }
    if !contains(arm64_dump, "issa_vgraph=vgraph(") {
        return 1
    }
    if !contains(arm64_dump, "issa_dom=dom(") {
        return 1
    }
    if !contains(arm64_dump, "issa_loops=loops(") {
        return 1
    }
    if !contains(arm64_dump, "issa_mdep=mdep(") {
        return 1
    }
    if !contains(arm64_dump, "issa_rplan=rplan(") {
        return 1
    }
    if !contains(arm64_dump, "bb0->bb1") {
        return 1
    }
    if !contains(arm64_dump, "v0->v1") {
        return 1
    }
    if !contains(arm64_dump, "bb0>bb1") {
        return 1
    }
    if !contains(arm64_dump, "sample=store0->load0") {
        return 1
    }
    if !contains(arm64_dump, "sample=pcopy(v0->v1)") {
        return 1
    }

    var margin_override_dump = dump_pipeline(build_pipeline_with_margin(mir_text, "arm64", 99))
    if !contains(margin_override_dump, "delta_hot=") {
        return 1
    }
    if !contains(margin_override_dump, ",margin=99,") {
        return 1
    }

    var hot_balanced = build_pass_delta_hot_summary("constfold=1,gvn=1", "constfold=1,gvn=2", -1)
    if !contains(hot_balanced, ",dominant=balanced") {
        return 1
    }
    var hot_struct = build_pass_delta_hot_summary("constfold=6,gvn=4", "constfold=1,gvn=0", -1)
    if !contains(hot_struct, ",dominant=struct") {
        return 1
    }
    var hot_value = build_pass_delta_hot_summary("constfold=1,gvn=0", "constfold=5,gvn=3", -1)
    if !contains(hot_value, ",dominant=value") {
        return 1
    }
    var hot_forced_balanced = build_pass_delta_hot_summary("constfold=6,gvn=4", "constfold=1,gvn=0", 99)
    if !contains(hot_forced_balanced, ",margin=99,dominant=balanced") {
        return 1
    }

    var tie_reason = instruction_verify_pick_reason("shape", "cfg=1,rerun=1", "cfg")
    if tie_reason != "tie-break" {
        return 1
    }
    var fallback_reason = instruction_verify_pick_reason("shape", "cfg=2,rerun=1", "rerun")
    if fallback_reason != "fallback" {
        return 1
    }

    var invalid_dump = dump_pipeline(build_pipeline("broken", "amd64"))
    if !contains(invalid_dump, "issa_verify=") {
        return 1
    }
    if contains(invalid_dump, "issa_verify=0") {
        return 1
    }
    if !contains(invalid_dump, "issa_verify_code=") {
        return 1
    }
    if contains(invalid_dump, "issa_verify_code=0") {
        return 1
    }
    if !contains(invalid_dump, "issa_verify_flags=") {
        return 1
    }
    if contains(invalid_dump, "issa_verify_flags=ok") {
        return 1
    }
    if !contains(invalid_dump, "issa_verify_primary=") {
        return 1
    }
    if contains(invalid_dump, "issa_verify_primary=ok") {
        return 1
    }
    if !contains(invalid_dump, "issa_verify_stage=") {
        return 1
    }
    if contains(invalid_dump, "issa_verify_stage=none") {
        return 1
    }
    if !contains(invalid_dump, "issa_verify_evidence=") {
        return 1
    }
    if contains(invalid_dump, "issa_verify_evidence=none") {
        return 1
    }
    if !contains(invalid_dump, "primary=") {
        return 1
    }
    if !contains(invalid_dump, "picked=") {
        return 1
    }
    if !contains(invalid_dump, "top=") {
        return 1
    }
    if !contains(invalid_dump, "second=") {
        return 1
    }
    if !contains(invalid_dump, "issa_verify_pick_top=true") {
        return 1
    }
    if !contains(invalid_dump, "issa_verify_pick_reason=") {
        return 1
    }
    if contains(invalid_dump, "issa_verify_pick_reason=ok") {
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
    if !contains(heavy_dump, "mir_opt=mir heavy") {
        return 1
    }
    if !contains(heavy_dump, "const=2") {
        return 1
    }
    if !contains(heavy_dump, "bb0(entry) stmts=") {
        return 1
    }
    if !contains(heavy_dump, "bb0(entry) stmts=5 const=2 term=jump") {
        return 1
    }

    var coalesce_mir = "mir coalesce blocks=3 entry=0 exit=2 | bb0(entry) stmts=1 term=jump | bb1(dead) stmts=0 term=jump | bb2(exit) stmts=0 term=return"
    var coalesce_dump = dump_pipeline(build_pipeline(coalesce_mir, "amd64"))
    if !contains(coalesce_dump, "mir_opt=mir coalesce blocks=2") {
        return 1
    }
    if contains(coalesce_dump, "bb1(dead) stmts=0 term=jump") {
        return 1
    }
    if !contains(coalesce_dump, "blocks=2") {
        return 1
    }

    var rerun_mir = "mir rerun blocks=3 entry=0 exit=2 | bb0(entry) stmts=0 term=branch | bb1(mid) stmts=0 term=jump | bb2(exit) stmts=0 term=return"
    var rerun_dump = dump_pipeline(build_pipeline(rerun_mir, "amd64"))
    if !contains(rerun_dump, "invalid_reruns=") {
        return 1
    }
    if !contains(rerun_dump, "mir_opt=mir rerun blocks=2") {
        return 1
    }
    if contains(rerun_dump, "bb0(entry) stmts=0 term=jump | bb1(mid) stmts=0 term=jump") {
        return 1
    }

    var value_mir = "mir value blocks=5 entry=0 exit=4 | bb0(entry) stmts=4 phi=3 copy=4 term=branch | bb1(left) stmts=2 term=jump | bb2(right) stmts=2 term=jump | bb3(join) stmts=1 copy=1 term=branch | bb4(exit) stmts=1 term=return"
    var value_dump = dump_pipeline(build_pipeline(value_mir, "amd64"))
    if !contains(value_dump, "mir_opt=mir value") {
        return 1
    }
    if !contains(value_dump, "phi=2") {
        return 1
    }
    if !contains(value_dump, "copy=1") {
        return 1
    }

    var memory_mir = "mir memory blocks=4 entry=0 exit=3 | bb0(entry) stmts=5 load=4 store=2 term=branch | bb1(loop) stmts=1 term=branch | bb2(latch) stmts=0 term=jump | bb3(exit) stmts=1 term=return"
    var memory_dump = dump_pipeline(build_pipeline(memory_mir, "amd64"))
    if !contains(memory_dump, "mir_opt=mir memory") {
        return 1
    }
    if !contains(memory_dump, "load=2") {
        return 1
    }
    if !contains(memory_dump, "store=1") {
        return 1
    }

    var memphi_mir = "mir memphi blocks=4 entry=0 exit=3 | bb0(entry) stmts=4 memphi=3 load=2 store=1 term=branch | bb1(left) stmts=1 term=jump | bb2(join) stmts=1 phi=1 term=jump | bb3(exit) stmts=1 term=return"
    var memphi_dump = dump_pipeline(build_pipeline(memphi_mir, "amd64"))
    if !contains(memphi_dump, "mir_opt=mir memphi") {
        return 1
    }
    if !contains(memphi_dump, "memphi=2") {
        return 1
    }
    if !contains(memphi_dump, "memssa_chain=") {
        return 1
    }
    if !contains(value_dump, "mir_trace=input=mir value") {
        return 1
    }
    if !contains(value_dump, ";pre=mir value") {
        return 1
    }
    if !contains(memory_dump, ";cfg=mir memory") {
        return 1
    }
    if !contains(memory_dump, ";licm=mir memory") {
        return 1
    }
    if !contains(memory_dump, ";bce=mir memory") {
        return 1
    }
    if !contains(memory_dump, "mir_delta=constfold:") {
        return 1
    }
    if !contains(memory_dump, ";bce:") {
        return 1
    }
    if !contains(memory_dump, "delta_summary=") {
        return 1
    }
    if !contains(memory_dump, "delta_struct=") {
        return 1
    }
    if !contains(memory_dump, "delta_value=") {
        return 1
    }
    if !contains(memory_dump, "delta_hot=struct=") {
        return 1
    }
    if !contains(memory_dump, "),value=") {
        return 1
    }
    if !contains(memory_dump, "/") {
        return 1
    }
    if !contains(memory_dump, ",margin=") {
        return 1
    }
    if !contains(memory_dump, ",dominant=") {
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