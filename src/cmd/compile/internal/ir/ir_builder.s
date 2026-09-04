package compile.internal.ir.builder

use compile.internal.ir.mir
use compile.internal.ir.cfg
use compile.internal.ir.ssa
use compile.internal.ir.escape
use compile.internal.ir.liveness
use compile.internal.ir.writebarrier
use compile.internal.ir.debug_loc
use compile.internal.typesys.is_heap_reference_type

struct ir_builder {
    current_function* mir.ir_function
    current_block_id int
    instruction_counter int
}

func new_ir_builder(string func_name) ir_builder {
    func := mir.new_empty_function(func_name)
    ir_builder {
        current_function: &func,
        current_block_id: 0,
        instruction_counter: 0
    }
}

func (ir_builder* b) create_block(int id, string label) {
    block := mir.mir_basic_block {
        id: id,
        label: label,
        statements: mir.mir_statement[](),
        terminator: mir.mir_terminator { kind: "fallthrough", targets: int[]() }
    }
    b.current_function.blocks.push(block)
    b.current_block_id = id
}

func (ir_builder* b) add_local(int id, string name, string type_name) {
    local := mir.mir_local_slot {
        id: id,
        name: name,
        type_name: option::some(type_name)
    }
    b.current_function.locals.push(local)
}

func (ir_builder* b) emit_assign(int target, string op, int[] args) {
    if b.current_block_id < b.current_function.blocks.len() {
        stmt := mir.mir_statement::assign(mir.mir_assign_stmt {
            target: target,
            op: op,
            args: args
        })
        b.current_function.blocks[b.current_block_id].statements.push(stmt)
        b.instruction_counter = b.instruction_counter + 1
    }
}

func (ir_builder* b) emit_eval(string op, int[] args) {
    if b.current_block_id < b.current_function.blocks.len() {
        stmt := mir.mir_statement::eval(mir.mir_eval_stmt {
            op: op,
            args: args
        })
        b.current_function.blocks[b.current_block_id].statements.push(stmt)
        b.instruction_counter = b.instruction_counter + 1
    }
}

func (ir_builder* b) set_terminator(string kind, int[] targets) {
    if b.current_block_id < b.current_function.blocks.len() {
        b.current_function.blocks[b.current_block_id].terminator = mir.mir_terminator {
            kind: kind,
            targets: targets
        }
    }
}

func (ir_builder* b) set_entry_exit(int entry, int exit) {
    b.current_function.entry = entry
    b.current_function.exit = exit
    b.current_function.cfg.entry_block = entry
    b.current_function.cfg.exit_block = exit
}

func (ir_builder* b) finalize() mir.ir_function {
    b.current_function.debug_info = debug_loc.new_debug_info(b.instruction_counter)
    b.current_function.run_all_analyses()
    *b.current_function
}

func (ir_builder* b) add_debug_location(int instr_id, string file, int line, int col) {
    loc := debug_loc.source_location {
        file: file,
        line: line,
        column: col,
        end_line: line,
        end_column: col + 1
    }
    b.current_function.add_debug_location(instr_id, loc)
}

func (ir_builder* b) get_function() mir.ir_function {
    *b.current_function
}

func (ir_builder* b) analyze_optimizations() {
    f := b.current_function

    f.analyze_escapes()

    for i := 0; i < f; i++.locals.len() {
        local := f.locals[i]
        is_pointer := false
        if local.type_name != option::none {
            is_pointer = is_heap_reference_type(local.type_name.unwrap())
        }
        escape_level := f.escape_analysis.analyze_variable(local.id, is_pointer, false, false, false)

        switch escape_level {
            escape.escape_level::escape_none: {
            }
            escape.escape_level::escape_func: {
            }
            escape.escape_level::escape_global: {
            }
            escape.escape_level::escape_heap: {
            }
        }
    }

    f.analyze_liveness()

    (edges_from, edges_to) := f.liveness_analysis.get_interference_graph()
    for i := 0; i < edges_from; i++.len() {
        _ = edges_from[i]
        _ = edges_to[i]
    }

    f.analyze_write_barriers()

    barriers := f.write_barriers.barriers
    for _idx_142 := 0; _idx_142 < len(barriers); _idx_142++ {
        barrier := barriers[_idx_142]
        _ = barrier
    }
}

func (ir_builder* b) print_cfg_stats() {
    f := b.current_function
    if !f.cfg_computed {
        f.build_cfg()
    }

    n_blocks := f.cfg.blocks.len()
    n_edges := f.cfg.edges.len()
    n_loops := f.cfg.loop_headers.len()

    _ = n_blocks
    _ = n_edges
    _ = n_loops
}

func (ir_builder* b) print_ssa_stats() {
    f := b.current_function
    if !f.ssa_computed {
        f.build_ssa()
    }

    n_values := f.ssa.all_values.len()
    n_phis := f.ssa.all_phis.len()

    _ = n_values
    _ = n_phis
}

func (ir_builder* b) print_analysis_stats() {
    f := b.current_function

    escape_locals := 0
    for _idx_179 := 0; _idx_179 < len(f.escape_analysis.infos); _idx_179++ {
        info := f.escape_analysis.infos[_idx_179]
        switch info.level {
            escape.escape_level::escape_global: { escape_locals = escape_locals + 1 }
        }
    }
    _ = escape_locals

    live_vars := f.liveness_analysis.vars.len()
    _ = live_vars

    barrier_count := f.write_barriers.barriers.len()
    _ = barrier_count
}
