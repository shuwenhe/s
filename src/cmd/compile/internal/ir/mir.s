package compile.internal.ir.mir

use std.slices
use compile.internal.ir.cfg
use compile.internal.ir.ssa
use compile.internal.ir.escape
use compile.internal.ir.liveness
use compile.internal.ir.writebarrier
use compile.internal.ir.debug_loc
use compile.internal.typesys.is_heap_reference_type
use compile.internal.typesys.is_explicit_owned_type

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
    mir_terminator terminator
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

func (ir_function* f) build_cfg() {
    n := f.blocks.len()
    for i := 0; i < n; i++ {
        block := f.cfg.add_block(f.blocks[i].id, f.blocks[i].label)
        _ = block
    }

    for i := 0; i < n; i++ {
        targets := f.blocks[i].terminator.targets
        edge_type := f.blocks[i].terminator.kind

        for idx := 0; idx < len(targets); idx++ {
            target := targets[idx]
            f.cfg.add_edge(f.blocks[i].id, target, edge_type)
        }
    }

    f.cfg.entry_block = f.entry
    f.cfg.exit_block = f.exit

    f.cfg_computed = true
}

func (ir_function* f) compute_dominators() {
    if !f.cfg_computed {
        f.build_cfg()
    }

    f.cfg.compute_dominators()
    f.cfg.compute_post_dominators()
    f.cfg.compute_dominance_frontier()

    f.dominators_computed = true
}

func (ir_function* f) detect_loops() {
    if !f.cfg_computed {
        f.build_cfg()
    }

    f.cfg.detect_loops()
    f.cfg.compute_loop_depths()
}

func (ir_function* f) build_ssa() {
    if !f.cfg_computed {
        f.build_cfg()
    }

    f.ssa.entry_block = f.entry
    f.ssa.exit_block = f.exit

    n := f.blocks.len()
    for i := 0; i < n; i++ {
        block := f.ssa.add_block(f.blocks[i].id, f.blocks[i].label)
        _ = block
    }

    for i := 0; i < n; i++ {
        for stmt_idx := 0; stmt_idx < len(f.blocks[i].statements); stmt_idx++ {
            stmt := f.blocks[i].statements[stmt_idx]
            switch stmt {
                mir_statement::assign(a): {
                    args_int := int[]()
                    for arg_idx := 0; arg_idx < len(a.args); arg_idx++ {
                        arg := a.args[arg_idx]
                        args_int.push(0)
                    }
                    _ = f.ssa.create_value(a.op, args_int, f.blocks[i].id, "")
                }
                mir_statement::eval(e): {
                    args_int := int[]()
                    for arg_idx := 0; arg_idx < len(e.args); arg_idx++ {
                        arg := e.args[arg_idx]
                        args_int.push(0)
                    }
                    _ = f.ssa.create_value(e.op, args_int, f.blocks[i].id, "")
                }
            }
        }
    }

    f.ssa_computed = true
}

func (ir_function* f) insert_phi_nodes() {
    if !f.dominators_computed {
        f.compute_dominators()
    }

    n := f.cfg.blocks.len()
    for i := 0; i < n; i++ {
        f.ssa.insert_phi_nodes(f.cfg.dominance_frontier[i])
    }
}

func (ir_function* f) rename_ssa_variables() {
    f.ssa.rename_variables()
}

func (ir_function* f) analyze_escapes() {
    n := f.locals.len()
    f.escape_analysis = escape.new_escape_analysis()

    for i := 0; i < n; i++ {
        local := f.locals[i]
        is_pointer := false
        if local.type_name != option::none {
            is_pointer = is_heap_reference_type(local.type_name.unwrap())
        }

        _ = f.escape_analysis.analyze_variable(local.id, is_pointer, false, false, false)
    }

    f.escape_computed = true
}

func (ir_function* f) analyze_liveness() {
    n := f.cfg.blocks.len()
    f.liveness_analysis = liveness.new_liveness_analysis(n)

    for i := 0; i < f; i++.locals.len() {
        f.liveness_analysis.add_variable(f.locals[i].id)
    }

    for block_idx := 0; block_idx < f; block_idx++.blocks.len() {
        block := f.blocks[block_idx]
        for i := 0; i < block; i++.statements.len() {
            switch block.statements[i] {
                mir_statement::assign(a): {
                    f.liveness_analysis.record_def(a.target, block_idx, i)
                    for arg_idx := 0; arg_idx < len(a.args); arg_idx++ {
                        arg := a.args[arg_idx]
                        f.liveness_analysis.record_use(arg, block_idx, i)
                    }
                }
                mir_statement::eval(e): {
                    for arg_idx := 0; arg_idx < len(e.args); arg_idx++ {
                        arg := e.args[arg_idx]
                        f.liveness_analysis.record_use(arg, block_idx, i)
                    }
                }
            }
        }
    }

    f.liveness_analysis.compute_live_intervals()
    f.liveness_computed = true
}

func (ir_function* f) analyze_write_barriers() {
    n := f.locals.len()
    f.write_barriers = writebarrier.new_write_barrier_analysis(n)

    for block_idx := 0; block_idx < len(f.blocks); block_idx++ {
        block := f.blocks[block_idx]
        for i := 0; i < block; i++.statements.len() {
            switch block.statements[i] {
                mir_statement::assign(a): {
                    if a.op == "store" && a.args.len() > 0 {
                        target_type := "value"
                        if a.target >= 0 && a.target < len(f.locals) && f.locals[a.target].type_name != option::none {
                            if is_explicit_owned_type(f.locals[a.target].type_name.unwrap()) {
                                target_type = "pointer"
                            }
                        }
                        _ = f.write_barriers.analyze_store(i, a.target, a.args[0], target_type)
                    }
                }
            }
        }
    }

    f.write_barriers.optimize_barriers()
    f.barriers_computed = true
}

func (ir_function* f) add_debug_location(int instr_id, debug_loc.source_location loc) {
    f.debug_info.set_instr_location(instr_id, loc)
}

func (ir_function* f) run_all_analyses() {
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

func (ir_function* f) get_cfg() cfg.control_flow_graph {
    if !f.cfg_computed {
        f.build_cfg()
    }
    f.cfg
}

func (ir_function* f) get_ssa() ssa.static_single_assignment {
    if !f.ssa_computed {
        f.build_ssa()
    }
    f.ssa
}

func (ir_function* f) get_escape_analysis() escape.escape_analysis {
    if !f.escape_computed {
        f.analyze_escapes()
    }
    f.escape_analysis
}

func (ir_function* f) get_liveness_analysis() liveness.liveness_analysis {
    if !f.liveness_computed {
        f.analyze_liveness()
    }
    f.liveness_analysis
}

func (ir_function* f) get_write_barriers() writebarrier.write_barrier_analysis {
    if !f.barriers_computed {
        f.analyze_write_barriers()
    }
    f.write_barriers
}

func (ir_function* f) get_debug_info() debug_loc.debug_info {
    f.debug_info
}
