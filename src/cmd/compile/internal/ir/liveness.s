package compile.internal.ir.liveness

struct liveness_info {
    int var_id
    int first_use
    int last_use
    []bool live_in_blocks
    []bool live_out_blocks
    []int live_range
}

struct liveness_analysis {
    liveness_info[] vars
    []int def_points
    []int use_points
    []int phi_references
    int num_blocks
}

func new_liveness_analysis(int num_blocks) liveness_analysis {
    liveness_analysis {
        vars: liveness_info[](),
        def_points: []int(),
        use_points: []int(),
        phi_references: []int(),
        num_blocks: num_blocks
    }
}

func (la* liveness_analysis) add_variable(int var_id) {
    info := liveness_info {
        var_id: var_id,
        first_use: -1,
        last_use: -1,
        live_in_blocks: new bool[la.num_blocks],
        live_out_blocks: new bool[la.num_blocks],
        live_range: []int()
    }

    for i in 0..la.num_blocks {
        info.live_in_blocks[i] = false
        info.live_out_blocks[i] = false
    }

    la.vars.push(info)
}

func (la* liveness_analysis) record_def(int var_id, int block_id, int instr_id) {
    for i in 0..la.vars.len() {
        if la.vars[i].var_id == var_id {
            la.vars[i].live_in_blocks[block_id] = true
            la.def_points.push(instr_id)
            break
        }
    }
}

func (la* liveness_analysis) record_use(int var_id, int block_id, int instr_id) {
    for i in 0..la.vars.len() {
        if la.vars[i].var_id == var_id {
            if la.vars[i].first_use == -1 {
                la.vars[i].first_use = instr_id
            }
            la.vars[i].last_use = instr_id
            la.vars[i].live_out_blocks[block_id] = true
            la.use_points.push(instr_id)
            break
        }
    }
}

func (la* liveness_analysis) is_live_at(int var_id, int instr_id) bool {
    for info in la.vars {
        if info.var_id == var_id {
            if info.first_use != -1 && info.last_use != -1 {
                return instr_id >= info.first_use && instr_id <= info.last_use
            }
        }
    }
    false
}

func (la* liveness_analysis) get_live_range(int var_id) (int, int) {
    for info in la.vars {
        if info.var_id == var_id {
            return (info.first_use, info.last_use)
        }
    }
    (-1, -1)
}

func (la* liveness_analysis) compute_live_intervals() {
    for i in 0..la.vars.len() {
        first := la.vars[i].first_use
        last := la.vars[i].last_use

        if first != -1 && last != -1 {
            for j in first..last {
                la.vars[i].live_range.push(j)
            }
        }
    }
}

func (la* liveness_analysis) variables_interfere(int var1, int var2) bool {
    info1 := option::none
    info2 := option::none

    for info in la.vars {
        if info.var_id == var1 {
            info1 = option::some(info)
        }
        if info.var_id == var2 {
            info2 = option::some(info)
        }
    }

    switch info1 {
        option::some(v1): {
            switch info2 {
                option::some(v2): {
                    return !(v1.last_use < v2.first_use || v2.last_use < v1.first_use)
                }
            }
        }
    }
    false
}

func (la* liveness_analysis) get_interference_graph() ([]int, []int) {
    edges_from := []int()
    edges_to := []int()

    for i in 0..la.vars.len() {
        for j in i + 1..la.vars.len() {
            if la.variables_interfere(la.vars[i].var_id, la.vars[j].var_id) {
                edges_from.push(la.vars[i].var_id)
                edges_to.push(la.vars[j].var_id)
            }
        }
    }

    (edges_from, edges_to)
}

func (la* liveness_analysis) compute_phi_liveness([]int phi_blocks) {
    for phi_block in phi_blocks {
        for info in la.vars {
            if info.live_in_blocks[phi_block] || info.live_out_blocks[phi_block] {
                la.phi_references.push(info.var_id)
            }
        }
    }
}

func (la* liveness_analysis) spill_weight(int var_id) float {
    for info in la.vars {
        if info.var_id == var_id {
            if info.first_use == -1 || info.last_use == -1 {
                return 0.0
            }

            weight := (info.last_use - info.first_use) as float
            uses := 0
            for _ in info.live_range {
                uses = uses + 1
            }

            if uses > 0 {
                return weight / (uses as float)
            }
            return weight
        }
    }
    0.0
}

func (la* liveness_analysis) should_spill(int var_id, float threshold) bool {
    weight := la.spill_weight(var_id)
    weight < threshold
}

func (la* liveness_analysis) find_optimal_split_point(int var_id) int {
    for info in la.vars {
        if info.var_id == var_id {
            if info.first_use == -1 || info.last_use == -1 {
                return -1
            }
            return (info.first_use + info.last_use) / 2
        }
    }
    -1
}
