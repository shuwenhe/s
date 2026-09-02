package internal.ssa

func enable_all_optimizations() int {
    init_optimization_pipeline()
    init_opt_stats()
    init_generic_rules()
    init_const_fold_rules()
    init_algebraic_rules()
    
    return 0
}

func compile_with_optimizations(ssa_func* func) int {
    if func == 0 {
        return -1
    }
    
    eprintln("Starting optimization pipeline...\n")
    
    int result = run_all_optimization_passes(func)
    
    print_detailed_stats()
    
    return result
}

func optimize_and_lower(ssa_func* func) ssa_func* {
    if func == 0 {
        return 0
    }
    
    compile_with_optimizations(func)
    
    return func
}
