package compile.internal.ir.examples

use compile.internal.ir.builder
use compile.internal.ir.mir
use compile.internal.ir.cfg
use compile.internal.ir.ssa
use compile.internal.ir.escape
use compile.internal.ir.liveness
use compile.internal.ir.writebarrier
use compile.internal.ir.debug_loc

func example_simple_function() mir.ir_function {
    b := builder.new_ir_builder("simple_add")

    b.add_local(1, "a", "int")
    b.add_local(2, "b", "int")
    b.add_local(3, "result", "int")

    b.create_block(0, "entry")
    b.emit_assign(3, "add", []int{1, 2})
    b.set_terminator("return", []int{})

    b.set_entry_exit(0, 0)

    b.add_debug_location(0, "example.s", 10, 5)

    b.finalize()
}

func example_loop_function() mir.ir_function {
    b := builder.new_ir_builder("loop_sum")

    b.add_local(1, "n", "int")
    b.add_local(2, "i", "int")
    b.add_local(3, "sum", "int")

    b.create_block(0, "entry")
    b.emit_assign(2, "const", []int{})
    b.emit_assign(3, "const", []int{})
    b.set_terminator("br", []int{1})

    b.create_block(1, "loop_header")
    b.emit_eval("cmp_lt", []int{2, 1})
    b.set_terminator("br_cond", []int{2, 3})

    b.create_block(2, "loop_body")
    b.emit_assign(3, "add", []int{3, 2})
    b.emit_assign(2, "add", []int{2, 1})
    b.set_terminator("br", []int{1})

    b.create_block(3, "exit")
    b.set_terminator("return", []int{})

    b.set_entry_exit(0, 3)

    b.add_debug_location(0, "example.s", 20, 5)
    b.add_debug_location(1, "example.s", 21, 5)
    b.add_debug_location(2, "example.s", 23, 9)

    b.finalize()
}

func example_cfg_analysis(mir.ir_function f) {
    cfg := f.get_cfg()

    n_blocks := cfg.blocks.len()
    _ = n_blocks

    for i in 0..cfg.blocks.len() {
        block := cfg.blocks[i]
        n_pred := block.predecessors.len()
        n_succ := block.successors.len()
        _ = n_pred
        _ = n_succ
    }

    n_loop_headers := cfg.loop_headers.len()
    _ = n_loop_headers

    for header in cfg.loop_headers {
        loop_body := cfg.get_loop_body(header)
        _ = loop_body
    }
}

func example_ssa_analysis(mir.ir_function f) {
    ssa := f.get_ssa()

    n_values := ssa.all_values.len()
    n_phis := ssa.all_phis.len()

    _ = n_values
    _ = n_phis

    for i in 0..ssa.blocks.len() {
        block := ssa.blocks[i]
        for phi in block.phis {
            incoming := phi.incoming_values.len()
            _ = incoming
        }
    }
}

func example_escape_analysis(mir.ir_function f) {
    escape_info := f.get_escape_analysis()

    for info in escape_info.infos {
        escapes := false
        switch info.level {
            escape.escape_level::escape_none: {}
            escape.escape_level::escape_func: { escapes = true }
            escape.escape_level::escape_global: { escapes = true }
            escape.escape_level::escape_heap: { escapes = true }
        }
        _ = escapes
    }
}

func example_liveness_analysis(mir.ir_function f) {
    liveness := f.get_liveness_analysis()

    for var in liveness.vars {
        first_use := var.first_use
        last_use := var.last_use
        _ = first_use
        _ = last_use

        weight := liveness.spill_weight(var.var_id)
        _ = weight
    }

    (edges_from, edges_to) := liveness.get_interference_graph()
    n_interference_edges := edges_from.len()
    _ = n_interference_edges
    _ = edges_to
}

func example_write_barrier_analysis(mir.ir_function f) {
    barriers := f.get_write_barriers()

    for barrier in barriers.barriers {
        needs_barrier := barriers.needs_barrier(barrier.target_var)
        _ = needs_barrier

        switch barrier.kind {
            writebarrier.barrier_type::barrier_none: {}
            writebarrier.barrier_type::barrier_store: {}
            writebarrier.barrier_type::barrier_store_load: {}
            writebarrier.barrier_type::barrier_store_store: {}
            writebarrier.barrier_type::barrier_arr_write: {}
            writebarrier.barrier_type::barrier_slice_write: {}
        }
    }
}

func example_debug_info(mir.ir_function f) {
    debug := f.get_debug_info()

    n_scopes := debug.scopes.len()
    n_vars := debug.variables.len()
    _ = n_scopes
    _ = n_vars

    line_table := debug.generate_line_number_table()
    _ = line_table

    location_info := debug.generate_location_info()
    _ = location_info
}

func example_combined_optimization(mir.ir_function f) {
    cfg := f.get_cfg()
    ssa := f.get_ssa()
    escape_info := f.get_escape_analysis()
    liveness := f.get_liveness_analysis()
    barriers := f.get_write_barriers()

    for i in 0..cfg.blocks.len() {
        block := cfg.blocks[i]
        loop_depth := block.loop_depth

        for var in liveness.vars {
            if var.live_in_blocks[i] {
                should_spill := liveness.should_spill(var.var_id, 100.0)
                if should_spill && loop_depth > 0 {
                }
            }
        }
    }

    for info in escape_info.infos {
        local_var := info.var_id
        for barrier in barriers.barriers {
            if barrier.target_var == local_var {
                if info.level != escape.escape_level::escape_heap {
                }
            }
        }
    }
}

func example_full_analysis_pipeline() {
    f := example_loop_function()

    example_cfg_analysis(f)
    example_ssa_analysis(f)
    example_escape_analysis(f)
    example_liveness_analysis(f)
    example_write_barrier_analysis(f)
    example_debug_info(f)
    example_combined_optimization(f)
}
