package compile.internal.ssa

struct ssa_config {
    bool debug
    bool enable_rewrite
    bool enable_cse
    bool enable_copyelim
    bool enable_prove
    bool enable_dom
    bool enable_deadcode
    bool enable_schedule
    bool enable_regalloc
    int regalloc_register_count
}

func default_config() ssa_config {
    ssa_config {
        debug: false,
        enable_rewrite: true,
        enable_cse: true,
        enable_copyelim: true,
        enable_prove: true,
        enable_dom: true,
        enable_deadcode: true,
        enable_schedule: true,
        enable_regalloc: true,
        regalloc_register_count: 8,
    }
}

func with_debug(ssa_config cfg, bool on) ssa_config {
    ssa_config {
        debug: on,
        enable_rewrite: cfg.enable_rewrite,
        enable_cse: cfg.enable_cse,
        enable_copyelim: cfg.enable_copyelim,
        enable_prove: cfg.enable_prove,
        enable_dom: cfg.enable_dom,
        enable_deadcode: cfg.enable_deadcode,
        enable_schedule: cfg.enable_schedule,
        enable_regalloc: cfg.enable_regalloc,
        regalloc_register_count: cfg.regalloc_register_count,
    }
}
