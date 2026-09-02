package compile.internal.ir.writebarrier

enum barrier_type {
    barrier_none,
    barrier_store,
    barrier_store_load,
    barrier_store_store,
    barrier_arr_write,
    barrier_slice_write
}

struct write_barrier {
    int instr_id
    int target_var
    int source_var
    barrier_type kind
    bool needs_nil_check
    bool needs_bounds_check
}

struct write_barrier_analysis {
    write_barrier[] barriers
    int[] gc_safe_points
    bool[] var_needs_barrier
    int num_vars
}

func new_write_barrier_analysis(int num_vars) write_barrier_analysis {
    write_barrier_analysis {
        barriers: write_barrier[](),
        gc_safe_points: int[](),
        var_needs_barrier: new bool[num_vars],
        num_vars: num_vars
    }
}

func (wba* write_barrier_analysis) analyze_store(int instr_id, int target_var, int source_var, string target_type) barrier_type {
    kind := barrier_type::barrier_none

    if target_type == "pointer" || target_type == "interface" {
        kind = barrier_type::barrier_store
    }

    if kind != barrier_type::barrier_none {
        barrier := write_barrier {
            instr_id: instr_id,
            target_var: target_var,
            source_var: source_var,
            kind: kind,
            needs_nil_check: true,
            needs_bounds_check: false
        }
        wba.barriers.push(barrier)
        wba.var_needs_barrier[target_var] = true
    }

    kind
}

func (wba* write_barrier_analysis) analyze_array_write(int instr_id, int array_var, int index_var, int value_var, string elem_type) barrier_type {
    kind := barrier_type::barrier_none

    if elem_type == "pointer" || elem_type == "interface" {
        kind = barrier_type::barrier_arr_write
    }

    if kind != barrier_type::barrier_none {
        barrier := write_barrier {
            instr_id: instr_id,
            target_var: array_var,
            source_var: value_var,
            kind: kind,
            needs_nil_check: false,
            needs_bounds_check: true
        }
        wba.barriers.push(barrier)
        wba.var_needs_barrier[array_var] = true
    }

    kind
}

func (wba* write_barrier_analysis) analyze_slice_write(int instr_id, int slice_var, int index_var, int value_var, string elem_type) barrier_type {
    kind := barrier_type::barrier_none

    if elem_type == "pointer" || elem_type == "interface" {
        kind = barrier_type::barrier_slice_write
    }

    if kind != barrier_type::barrier_none {
        barrier := write_barrier {
            instr_id: instr_id,
            target_var: slice_var,
            source_var: value_var,
            kind: kind,
            needs_nil_check: false,
            needs_bounds_check: true
        }
        wba.barriers.push(barrier)
        wba.var_needs_barrier[slice_var] = true
    }

    kind
}

func (wba* write_barrier_analysis) needs_barrier(int var_id) bool {
    if var_id < wba.num_vars {
        return wba.var_needs_barrier[var_id]
    }
    false
}

func (wba* write_barrier_analysis) record_gc_safe_point(int instr_id) {
    wba.gc_safe_points.push(instr_id)
}

func (wba* write_barrier_analysis) is_gc_safe_point(int instr_id) bool {
    for sp in wba.gc_safe_points {
        if sp == instr_id {
            return true
        }
    }
    false
}

func (wba* write_barrier_analysis) get_barriers_in_range(int start, int end) write_barrier[] {
    result := write_barrier[]()
    for barrier in wba.barriers {
        if barrier.instr_id >= start && barrier.instr_id <= end {
            result.push(barrier)
        }
    }
    result
}

func (wba* write_barrier_analysis) optimize_barriers() {
    i := 0
    while i < wba.barriers.len() {
        if i + 1 < wba.barriers.len() {
            if wba.barriers[i].target_var == wba.barriers[i + 1].target_var &&
               wba.barriers[i].instr_id + 1 == wba.barriers[i + 1].instr_id {
                if wba.barriers[i].kind == barrier_type::barrier_store &&
                   wba.barriers[i + 1].kind == barrier_type::barrier_store {
                    wba.barriers[i].kind = barrier_type::barrier_store_store
                    wba.barriers[i + 1] = wba.barriers[wba.barriers.len() - 1]
                    wba.barriers = wba.barriers[0..wba.barriers.len() - 1]
                    continue
                }
            }
        }
        i = i + 1
    }
}

func (wba* write_barrier_analysis) insert_barrier_code(write_barrier wb) string[] {
    code := string[]()

    if wb.needs_nil_check {
        code.push("if target_var != nil {")
    }

    switch wb.kind {
        barrier_type::barrier_store: {
            code.push("runtime.write_barrier_store(target_var, source_var)")
        }
        barrier_type::barrier_arr_write: {
            code.push("runtime.write_barrier_arr(array_var, index_var, source_var)")
        }
        barrier_type::barrier_slice_write: {
            code.push("runtime.write_barrier_slice(slice_var, index_var, source_var)")
        }
    }

    if wb.needs_nil_check {
        code.push("}")
    }

    code
}
