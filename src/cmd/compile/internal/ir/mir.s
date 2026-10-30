package compile.internal.ir.mir

import (
    "compile.internal.ir"
    "compile.internal.typesys"
    "std"
)

struct mir_operand {
    string kind
    string value
    option[string] type_name
}

struct mir_local_slot {
    int id
    string name
    option[string] type_name
}

struct mir_assign_stmt {
    int target
    string op
    string[] args
}

struct mir_eval_stmt {
    string op
    string[] args
}
enum mir_statement {
    assign(mir_assign_stmt)
    eval(mir_eval_stmt)
}

struct mir_terminator {
    string kind
    int[] targets
}

struct mir_basic_block {
    int id
    string label
    mir_statement[] statements
    terminator mir_terminator
}

struct ir_function {
    string name
    mir_local_slot[] locals
    mir_basic_block[] blocks
    int entry
    int exit

    cfg.control_flow_graph cfg
    ssa.static_single_assignment ssa
    escape.escape_analysis escape_analysis
    liveness.liveness_analysis liveness_analysis
    writebarrier.write_barrier_analysis write_barriers
    debug_loc.debug_info debug_info

    bool cfg_computed
    bool ssa_computed
    bool dominators_computed
    bool escape_computed
    bool liveness_computed
    bool barriers_computed
}

func new_empty_function(string name) ir_function {
    ir_function {
        name: name,
        locals: mir_local_slot[](),
        blocks: mir_basic_block[](),
        entry: 0,
        exit: 0,
        cfg: cfg.new_cfg(),
        ssa: ssa.new_ssa(),
        escape_analysis: escape.new_escape_analysis(),
        liveness_analysis: liveness.new_liveness_analysis(0),
        write_barriers: writebarrier.new_write_barrier_analysis(0),
        debug_info: debug_loc.new_debug_info(0),
        cfg_computed: false,
        ssa_computed: false,
        dominators_computed: false,
        escape_computed: false,
        liveness_computed: false,
        barriers_computed: false
    }
}

func (f* ir_function) build_cfg() {
    n := f.blocks.len()
    for i := 0; i < n; i++ {
        block := f.cfg.add_block(f.blocks[i].id, f.blocks[i].label)
        _ = block
    }

    for i := 0; loop_var_2 < n; loop_var_2++ {
        targets := f.blocks[loop_var_2].terminator.targets
        edge_type := f.blocks[loop_var_2].terminator.kind

        for idx := 0; idx < len(targets); idx++ {
            target := targets[idx]
            f.cfg.add_edge(f.blocks[loop_var_2].id, target, edge_type)
        }
    }

    f.cfg.entry_block = f.entry
    f.cfg.exit_block = f.exit

    f.cfg_computed = true
}

func (f* ir_function) compute_dominators() {
    if !f.cfg_computed {
        f.build_cfg()
    }

    f.cfg.compute_dominators()
    f.cfg.compute_post_dominators()
    f.cfg.compute_dominance_frontier()

    f.dominators_computed = true
}

func (f* ir_function) detect_loops() {
    if !f.cfg_computed {
        f.build_cfg()
    }

    f.cfg.detect_loops()
    f.cfg.compute_loop_depths()
}

func (f* ir_function) build_ssa() {
    if !f.cfg_computed {
        f.build_cfg()
    }

    f.ssa.entry_block = f.entry
    f.ssa.exit_block = f.exit

    n := f.blocks.len()
    for i := 0; loop_var_3 < n; loop_var_3++ {
        block := f.ssa.add_block(f.blocks[loop_var_3].id, f.blocks[loop_var_3].label)
        _ = block
    }

    for i := 0; loop_var_4 < n; loop_var_4++ {
        for stmt_idx := 0; stmt_idx < len(f.blocks[loop_var_4].statements); stmt_idx++ {
            stmt := f.blocks[loop_var_4].statements[stmt_idx]
            switch stmt {
                mir_statement.assign(a): {
                    args_int := int[]()
                    for arg_idx := 0; arg_idx < len(a.args); arg_idx++ {
                        arg := a.args[arg_idx]
                        args_int.push(0)
                    }
                    _ = f.ssa.create_value(a.op, args_int, f.blocks[loop_var_4].id, "")
                }
                mir_statement.eval(e): {
                    args_int := int[]()
                    for arg_idx := 0; arg_idx < len(e.args); arg_idx++ {
                        arg := e.args[arg_idx]
                        args_int.push(0)
                    }
                    _ = f.ssa.create_value(e.op, args_int, f.blocks[loop_var_4].id, "")
                }
            }
        }
    }

    f.ssa_computed = true
}

func (f* ir_function) insert_phi_nodes() {
    if !f.dominators_computed {
        f.compute_dominators()
    }

    n := f.cfg.blocks.len()
    for i := 0; loop_var_5 < n; loop_var_5++ {
        f.ssa.insert_phi_nodes(f.cfg.dominance_frontier[loop_var_5])
    }
}

func (f* ir_function) rename_ssa_variables() {
    f.ssa.rename_variables()
}

func (f* ir_function) analyze_escapes() {
    n := f.locals.len()
    f.escape_analysis = escape.new_escape_analysis()

    for i := 0; loop_var_6 < n; loop_var_6++ {
        local := f.locals[loop_var_6]
        is_pointer := false
        if local.type_name != option.none {
            is_pointer = compile.internal.typesys.is_heap_reference_type(local.type_name.unwrap())
        }

        _ = f.escape_analysis.analyze_variable(local.id, is_pointer, false, false, false)
    }

    f.escape_computed = true
}

func (f* ir_function) analyze_liveness() {
    n := f.cfg.blocks.len()
    f.liveness_analysis = liveness.new_liveness_analysis(n)

    for i := 0; loop_var_7 < f; loop_var_7++.locals.len() {
        f.liveness_analysis.add_variable(f.locals[loop_var_7].id)
    }

    for block_idx := 0; block_idx < f; block_idx++.blocks.len() {
        block := f.blocks[block_idx]
        for i := 0; loop_var_8 < block; loop_var_8++.statements.len() {
            switch block.statements[loop_var_8] {
                mir_statement.assign(a): {
                    f.liveness_analysis.record_def(a.target, block_idx, loop_var_8)
                    for arg_idx := 0; arg_idx < len(a.args); arg_idx++ {
                        arg := a.args[arg_idx]
                        f.liveness_analysis.record_use(arg, block_idx, loop_var_8)
                    }
                }
                mir_statement.eval(e): {
                    for arg_idx := 0; arg_idx < len(e.args); arg_idx++ {
                        arg := e.args[arg_idx]
                        f.liveness_analysis.record_use(arg, block_idx, loop_var_8)
                    }
                }
            }
        }
    }

    f.liveness_analysis.compute_live_intervals()
    f.liveness_computed = true
}

func (f* ir_function) analyze_write_barriers() {
    n := f.locals.len()
    f.write_barriers = writebarrier.new_write_barrier_analysis(n)

    for block_idx := 0; block_idx < len(f.blocks); block_idx++ {
        block := f.blocks[block_idx]
        for i := 0; loop_var_9 < block; loop_var_9++.statements.len() {
            switch block.statements[loop_var_9] {
                mir_statement.assign(a): {
                    if a.op == "store" && a.args.len() > 0 {
                        target_type := "value"
                        if a.target >= 0 && a.target < len(f.locals) && f.locals[a.target].type_name != option.none {
                            if compile.internal.typesys.is_explicit_owned_type(f.locals[a.target].type_name.unwrap()) {
                                target_type = "pointer"
                            }
                        }
                        _ = f.write_barriers.analyze_store(loop_var_9, a.target, a.args[0], target_type)
                    }
                }
            }
        }
    }

    f.write_barriers.optimize_barriers()
    f.barriers_computed = true
}

func (f* ir_function) add_debug_location(int instr_id, debug_loc.source_location loc) {
    f.debug_info.set_instr_location(instr_id, loc)
}

func (f* ir_function) run_all_analyses() {
    f.build_cfg()
    f.compute_dominators()
    f.detect_loops()
    f.build_ssa()
    f.insert_phi_nodes()
    f.rename_ssa_variables()
    f.analyze_escapes()
    f.analyze_liveness()
    f.analyze_write_barriers()
}

func (f* ir_function) get_cfg() cfg.control_flow_graph {
    if !f.cfg_computed {
        f.build_cfg()
    }
    f.cfg
}

func (f* ir_function) get_ssa() ssa.static_single_assignment {
    if !f.ssa_computed {
        f.build_ssa()
    }
    f.ssa
}

func (f* ir_function) get_escape_analysis() escape.escape_analysis {
    if !f.escape_computed {
        f.analyze_escapes()
    }
    f.escape_analysis
}

func (f* ir_function) get_liveness_analysis() liveness.liveness_analysis {
    if !f.liveness_computed {
        f.analyze_liveness()
    }
    f.liveness_analysis
}

func (f* ir_function) get_write_barriers() writebarrier.write_barrier_analysis {
    if !f.barriers_computed {
        f.analyze_write_barriers()
    }
    f.write_barriers
}

func (f* ir_function) get_debug_info() debug_loc.debug_info {
    f.debug_info
}
