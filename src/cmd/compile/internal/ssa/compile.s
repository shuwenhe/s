package compile.internal.ssa
use std.slices

struct pass_stat {
    string name
    int changed
}

struct compile_report {
    ssa_func f
    pass_stat[] stats
    prove_fact[] prove_facts
    dom_tree dom
    regalloc_result regalloc
    int check_code
    string dump
}

func optimize(ssa_func f, ssa_config cfg) pass_stat[] {
    stats := pass_stat[]()
    if cfg.enable_rewrite {
        stats = append(stats, pass_stat { name: "rewrite", changed: run_rewrite(f, cfg.target_arch) })
    }
    if cfg.enable_cse {
        stats = append(stats, pass_stat { name: "cse", changed: run_cse(f) })
    }
    if cfg.enable_copyelim {
        stats = append(stats, pass_stat { name: "copyelim", changed: run_copyelim(f) })
    }
    if cfg.enable_deadcode {
        stats = append(stats, pass_stat { name: "deadcode", changed: run_deadcode(f) })
    }
    if cfg.enable_schedule {
        stats = append(stats, pass_stat { name: "schedule", changed: run_schedule(f) })
    }
    stats
}

func compile_func(ssa_func f, ssa_config cfg) compile_report {
    stats := optimize(f, cfg)
    facts := prove_fact[]()
    if cfg.enable_prove {
        facts = run_prove(f)
        stats = append(stats, pass_stat { name: "prove", changed: len(facts) })
    }
    dominfo := run_dom(f)
    if cfg.enable_dom {
        stats = append(stats, pass_stat { name: "dom", changed: len(dominfo.block_ids) })
    }
    regs := regalloc_result {
        assigns: reg_assign[](),
        spills: 0,
    }
    if cfg.enable_regalloc {
        regs = run_regalloc(f, cfg.regalloc_register_count)
        stats = append(stats, pass_stat { name: "regalloc", changed: len(regs.assigns) })
    }
    code := check_func(f)
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
