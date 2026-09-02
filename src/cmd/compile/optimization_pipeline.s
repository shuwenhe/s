package optimization_pipeline

struct compilation_phase {
    int phase_id
    string phase_name
    int stats_time
    int stats_changes
}

struct optimization_stats {
    int total_phases
    int total_time
    int total_optimizations
    int code_size_before
    int code_size_after
    int instr_count_before
    int instr_count_after
}

struct optimization_pipeline {
    int phase_count
    compilation_phase[] phases
    optimization_stats stats
    int debug_enabled
}

func optimization_pipeline_new() optimization_pipeline* {
    pipeline := optimization_pipeline {
        phase_count: 0,
        phases: new compilation_phase[32],
        debug_enabled: 0,
        stats: optimization_stats {
            total_phases: 0,
            total_time: 0,
            total_optimizations: 0,
            code_size_before: 0,
            code_size_after: 0,
            instr_count_before: 0,
            instr_count_after: 0,
        },
        
    }
    &pipeline
}

func (pipeline* optimization_pipeline) register_phase(int phase_id, string phase_name) int {
    idx := pipeline.phase_count
    pipeline.phase_count = pipeline.phase_count + 1
    
    phase := compilation_phase {
        phase_id: phase_id,
        phase_name: phase_name,
        stats_time: 0,
        stats_changes: 0,
    }

    pipeline.phases[idx] = &phase
    idx
}

func (pipeline* optimization_pipeline) execute_pipeline(value[] all_values, block[] all_blocks, int num_blocks) int {
    pipeline.stats.code_size_before = compute_code_size(all_values)
    pipeline.stats.instr_count_before = len(all_values)
    
    phase := 0
    for phase < pipeline.phase_count {
        result := execute_optimization_phase(pipeline.phases[phase], all_values, all_blocks, num_blocks)
        
        pipeline.phases[phase].stats_changes = result
        pipeline.stats.total_optimizations = pipeline.stats.total_optimizations + result
        
        phase = phase + 1
    }
    
    pipeline.stats.code_size_after = compute_code_size(all_values)
    pipeline.stats.instr_count_after = len(all_values)
    
    0
}

func execute_optimization_phase(compilation_phase* phase, value[] all_values, block[] all_blocks, int num_blocks) int {
    if phase.phase_id == phase_ssa_construction {
        return execute_ssa_construction(all_values, all_blocks)
    } else {
        if phase.phase_id == phase_constant_folding {
            return execute_constant_folding(all_values)
        } else {
            if phase.phase_id == phase_dead_code_elim {
                return execute_dead_code_elim(all_values, all_blocks)
            } else {
                if phase.phase_id == phase_common_subexpr_elim {
                    return execute_cse(all_values)
                } else {
                    if phase.phase_id == phase_algebraic_simp {
                        return execute_algebraic_simp(all_values)
                    } else {
                        if phase.phase_id == phase_loop_invariant_cm {
                            return execute_licm(all_values, all_blocks)
                        } else {
                            if phase.phase_id == phase_strength_reduction {
                                return execute_strength_reduction(all_values)
                            } else {
                                if phase.phase_id == phase_inlining {
                                    return execute_inlining(all_values)
                                } else {
                                    if phase.phase_id == phase_escape_analysis {
                                        return execute_escape_analysis(all_values)
                                    } else {
                                        if phase.phase_id == phase_devirt {
                                            return execute_devirtualization(all_values)
                                        } else {
                                            if phase.phase_id == phase_liveness_analysis {
                                                return execute_liveness_analysis(all_blocks)
                                            } else {
                                                if phase.phase_id == phase_register_allocation {
                                                    return execute_register_allocation(all_values)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    return 0
}

func execute_ssa_construction(value[] all_values, block[] all_blocks) int {
    return len(all_values)
}

func execute_constant_folding(value[] all_values) int {
    changes := 0
    
    i := 0
    for i < len(all_values) {
        v := all_values[i]
        
        if v.op >= op_add && v.op <= op_xor {
            changes = changes + 1
        }
        
        i = i + 1
    }
    
    changes
}

func execute_dead_code_elim(value[] all_values, block[] all_blocks) int {
    changes := 0
    
    i := 0
    for i < len(all_values) {
        v := all_values[i]
        
        if v.op == op_store {
            changes = changes + 1
        }
        
        i = i + 1
    }
    
    changes
}

func execute_cse(value[] all_values) int {
    changes := 0
    
    i := 0
    for i < len(all_values) {
        j := i + 1
        for j < len(all_values) {
            if all_values[i].op == all_values[j].op {
                changes = changes + 1
            }
            j = j + 1
        }
        i = i + 1
    }
    
    changes
}

func execute_algebraic_simp(value[] all_values) int {
    changes := 0
    
    i := 0
    for i < len(all_values) {
        changes = changes + 1
        i = i + 1
    }
    
    changes
}

func execute_licm(value[] all_values, block[] all_blocks) int {
    changes := 0
    
    return changes
}

func execute_strength_reduction(value[] all_values) int {
    changes := 0
    
    i := 0
    for i < len(all_values) {
        v := all_values[i]
        
        if v.op == op_mul || v.op == op_div {
            changes = changes + 1
        }
        
        i = i + 1
    }
    
    changes
}

func execute_inlining(value[] all_values) int {
    changes := 0
    
    i := 0
    for i < len(all_values) {
        if all_values[i].op == op_call {
            changes = changes + 1
        }
        i = i + 1
    }
    
    changes
}

func execute_escape_analysis(value[] all_values) int {
    changes := 0
    
    return changes
}

func execute_devirtualization(value[] all_values) int {
    changes := 0
    
    i := 0
    for i < len(all_values) {
        if all_values[i].op == op_call {
            changes = changes + 1
        }
        i = i + 1
    }
    
    changes
}

func execute_liveness_analysis(block[] all_blocks) int {
    return len(all_blocks)
}

func execute_register_allocation(value[] all_values) int {
    return len(all_values)
}

func compute_code_size(value[] all_values) int {
    size := 0
    
    i := 0
    for i < len(all_values) {
        size = size + estimate_instr_size(all_values[i].op)
        i = i + 1
    }
    
    size
}

func estimate_instr_size(int op) int {
    if op == op_const {
        return 8
    } else {
        if op == op_load || op == op_store {
            return 8
        } else {
            if op == op_call {
                return 6
            } else {
                if op == op_branch {
                    return 6
                } else {
                    if op == op_cond_branch {
                        return 8
                    }
                }
            }
        }
    }
    
    return 4
}

func (pipeline* optimization_pipeline) print_stats() int {
    return 0
}

const phase_ssa_construction = 0
const phase_constant_folding = 1
const phase_dead_code_elim = 2
const phase_common_subexpr_elim = 3
const phase_algebraic_simp = 4
const phase_loop_invariant_cm = 5
const phase_strength_reduction = 6
const phase_inlining = 7
const phase_escape_analysis = 8
const phase_devirt = 9
const phase_liveness_analysis = 10
const phase_register_allocation = 11

const op_const = 2
const op_add = 3
const op_sub = 4
const op_mul = 5
const op_div = 6
const op_and = 8
const op_or = 9
const op_xor = 10
const op_load = 13
const op_store = 14
const op_call = 15
const op_branch = 17
const op_cond_branch = 18
