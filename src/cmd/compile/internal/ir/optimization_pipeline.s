package compile.internal.ir.optimization_framework

import (
    "compile.internal.ir.ssa_complete"
    "compile.internal.ir.dominance"
    "compile.internal.ir.alias"
    "compile.internal.ir.writebarrier_complete"
    "compile.internal.ir.liveness_complete"
    "compile.internal.ir.debug_loc_complete"
)

struct compiler_pipeline {
    ssa_function*[] functions
    dominator_tree*[] dominators
    liveness_analyzer*[] liveness_analyses
    alias_analysis*[] alias_analyses
    wb_inserter*[] write_barriers
    debug_loc_propagator*[] debug_propagators
    bool[] computed
}

func new_compiler_pipeline() compiler_pipeline* {
    cp := new(compiler_pipeline)
    cp.functions = new ssa_function*[]()
    cp.dominators = new dominator_tree*[]()
    cp.liveness_analyses = new liveness_analyzer*[]()
    cp.alias_analyses = new alias_analysis*[]()
    cp.write_barriers = new wb_inserter*[]()
    cp.debug_propagators = new debug_loc_propagator*[]()
    cp.computed = new bool[]()
    cp
}

func (cp compiler_pipeline*) add_function(name string) ssa_function* {
    func := new_ssa_function(name)
    cp.functions = append(cp.functions, func)
    cp.dominators = append(cp.dominators, nil)
    cp.liveness_analyses = append(cp.liveness_analyses, nil)
    cp.alias_analyses = append(cp.alias_analyses, nil)
    cp.write_barriers = append(cp.write_barriers, nil)
    cp.debug_propagators = append(cp.debug_propagators, nil)
    cp.computed = append(cp.computed, false)
    func
}

func (cp compiler_pipeline*) analyze_function(func_idx i32) {
    if func_idx < 0 || func_idx >= i32(len(cp.functions)) {
        return
    }
    
    func := cp.functions[func_idx]
    
    func.build_ssa()
    
    num_blocks := i32(len(func.blocks))
    
    if cp.dominators[func_idx] == nil {
        cp.dominators[func_idx] = new_dominator_tree(num_blocks)
        
        preds := make(i32[][], num_blocks)
        for i := i32(0); i < num_blocks; i += 1 {
            preds[i] = func.blocks[i].predecessors
        }
        
        cp.dominators[func_idx].compute_dominators(preds, func.entry_block)
        
        succs := make(i32[][], num_blocks)
        for i := i32(0); i < num_blocks; i += 1 {
            succs[i] = func.blocks[i].successors
        }
        cp.dominators[func_idx].compute_dominance_frontier(succs, preds)
    }
    
    if cp.liveness_analyses[func_idx] == nil {
        num_values := i32(len(func.values))
        cp.liveness_analyses[func_idx] = new_liveness_analyzer(num_values, num_blocks)
        
        for i := i32(0); i < num_blocks; i += 1 {
            block := func.blocks[i]
            for _, val := range block.values {
                cp.liveness_analyses[func_idx].mark_use(i, val.id)
            }
        }
        
        succs := make(i32[][], num_blocks)
        for i := i32(0); i < num_blocks; i += 1 {
            succs[i] = func.blocks[i].successors
        }
        cp.liveness_analyses[func_idx].compute_liveness(succs)
    }
    
    if cp.alias_analyses[func_idx] == nil {
        num_values := i32(len(func.values))
        cp.alias_analyses[func_idx] = new_alias_analysis(num_values)
    }
    
    if cp.write_barriers[func_idx] == nil {
        num_values := i32(len(func.values))
        cp.write_barriers[func_idx] = new_wb_inserter(num_values)
    }
    
    if cp.debug_propagators[func_idx] == nil {
        cp.debug_propagators[func_idx] = new_debug_loc_propagator()
    }
    
    cp.computed[func_idx] = true
}

func (cp compiler_pipeline*) get_dominator_tree(func_idx i32) dominator_tree* {
    if func_idx >= 0 && func_idx < i32(len(cp.dominators)) {
        return cp.dominators[func_idx]
    }
    nil
}

func (cp compiler_pipeline*) get_liveness_info(func_idx i32) liveness_analyzer* {
    if func_idx >= 0 && func_idx < i32(len(cp.liveness_analyses)) {
        return cp.liveness_analyses[func_idx]
    }
    nil
}

func (cp compiler_pipeline*) get_alias_info(func_idx i32) alias_analysis* {
    if func_idx >= 0 && func_idx < i32(len(cp.alias_analyses)) {
        return cp.alias_analyses[func_idx]
    }
    nil
}

func (cp compiler_pipeline*) get_write_barriers(func_idx i32) wb_inserter* {
    if func_idx >= 0 && func_idx < i32(len(cp.write_barriers)) {
        return cp.write_barriers[func_idx]
    }
    nil
}

func (cp compiler_pipeline*) get_debug_info(func_idx i32) debug_loc_propagator* {
    if func_idx >= 0 && func_idx < i32(len(cp.debug_propagators)) {
        return cp.debug_propagators[func_idx]
    }
    nil
}

func (cp compiler_pipeline*) run_optimization_pipeline() {
    for i := i32(0); i < i32(len(cp.functions)); i += 1 {
        cp.analyze_function(i)
        
        func := cp.functions[i]
        func.eliminate_dead_code()
        
        liveness := cp.get_liveness_info(i)
        if liveness != nil {
            for block_id := i32(0); block_id < i32(len(func.blocks)); block_id += 1 {
                live_vars := liveness.get_live_values(block_id)
                for _, val_id := range live_vars {
                    if val_id >= 0 && val_id < i32(len(func.values)) {
                        val := func.values[val_id]
                        if val != nil {
                        }
                    }
                }
            }
        }
    }
}

func (cp compiler_pipeline*) emit_debug_info() string {
    s := "Debug Information:\n"
    for i := i32(0); i < i32(len(cp.functions)); i += 1 {
        debug_info := cp.get_debug_info(i)
        if debug_info != nil {
            s += debug_info.to_string()
        }
    }
    s
}

func (cp compiler_pipeline*) to_string() string {
    s := "Compiler Optimization Pipeline:\n"
    s += "Functions: " + string(i32(len(cp.functions))) + "\n"
    
    for i := i32(0); i < i32(len(cp.functions)); i += 1 {
        if cp.functions[i] != nil {
            s += "  [" + string(i) + "] " + cp.functions[i].name
            if cp.computed[i] {
                s += " (analyzed)"
            }
            s += "\n"
        }
    }
    
    s
}
