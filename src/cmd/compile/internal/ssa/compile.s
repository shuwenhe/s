package compile.internal.ssa

use std.vec.vec

struct pass_stat {
    string name
    int changed
}

struct compile_report {
    ssa_func f
    vec[pass_stat] stats
    vec[prove_fact] prove_facts
    dom_tree dom
    regalloc_result regalloc
    int check_code
    string dump
}

func optimize(mut ssa_func f, ssa_config cfg) vec[pass_stat] {
    var stats = vec[pass_stat]()
    if cfg.enable_rewrite {
        stats.push(pass_stat { name: "rewrite", changed: run_rewrite(f, cfg.target_arch) })
    }
    if cfg.enable_cse {
        stats.push(pass_stat { name: "cse", changed: run_cse(f) })
    }
    if cfg.enable_copyelim {
        stats.push(pass_stat { name: "copyelim", changed: run_copyelim(f) })
    }
    if cfg.enable_deadcode {
        stats.push(pass_stat { name: "deadcode", changed: run_deadcode(f) })
    }
    if cfg.enable_schedule {
        stats.push(pass_stat { name: "schedule", changed: run_schedule(f) })
    }
    stats
}

func compile_func(mut ssa_func f, ssa_config cfg) compile_report {
    var stats = optimize(f, cfg)
    var facts = vec[prove_fact]()
    if cfg.enable_prove {
        facts = run_prove(f)
        stats.push(pass_stat { name: "prove", changed: facts.len() })
    }
    var dominfo = run_dom(f)
    if cfg.enable_dom {
        stats.push(pass_stat { name: "dom", changed: dominfo.block_ids.len() })
    }
    var regs = regalloc_result {
        assigns: vec[reg_assign](),
        spills: 0,
    }
    if cfg.enable_regalloc {
        regs = run_regalloc(f, cfg.regalloc_register_count)
        stats.push(pass_stat { name: "regalloc", changed: regs.assigns.len() })
    }
    var code = check_func(f)
    compile_report {
        f: f,
        stats: stats,
        prove_facts: facts,
        dom: dominfo,
        regalloc: regs,
        check_code: code,
        dump: dump_func(f),
    }
}
