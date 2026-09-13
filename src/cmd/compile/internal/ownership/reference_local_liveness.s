package reference_local_liveness


struct ref_local_occurrence {

    int ref_local_index


    int block_id


    int instr_index


    int occurrence_type
}


struct ref_local_use_def {

    int ref_local_index


    map[int]vec[int] uses_by_block


    map[int]vec[int] defs_by_block


    string place_repr
}


struct ref_liveness_point {

    int block_id
    int instr_index


    bool is_live
}


struct block_liveness {
    int block_id


    map[string]bool live_in


    map[string]bool live_out
}


func collect_ref_local_use_def(mir_module mir_module) map[int]ref_local_use_def {
    use_def_map := map[int]ref_local_use_def{}


    for f_idx := 0; f_idx < len(mir_module.functions); f_idx = f_idx + 1 {
        func := mir_module.functions[f_idx]


        for block_idx := 0; block_idx < len(func.blocks); block_idx = block_idx + 1 {
            block := func.blocks[block_idx]


            for instr_idx := 0; instr_idx < len(block.statements); instr_idx = instr_idx + 1 {
                stmt := block.statements[instr_idx]


                collect_from_statement(stmt, use_def_map, block.block_id, instr_idx)
            }
        }
    }

    return use_def_map
}

func collect_from_statement(
    stmt statement,
    use_def_map map[int]ref_local_use_def,
    block_id int,
    instr_idx int,
) {


    _ = stmt
    _ = use_def_map
    _ = block_id
    _ = instr_idx
}


func compute_block_liveness(
    func mir_func,
    use_def use_def_map,
) map[int]block_liveness {
    liveness := map[int]block_liveness{}


    for block_idx := 0; block_idx < len(func.blocks); block_idx = block_idx + 1 {
        block := func.blocks[block_idx]
        bl := block_liveness{
            block_id: block.block_id,
            live_in: map[string]bool{},
            live_out: map[string]bool{},
        }
        liveness[block.block_id] = bl
    }


    for iteration := 0; iteration < 100; iteration = iteration + 1 {
        changed := false


        for block_idx := 0; block_idx < len(func.blocks); block_idx = block_idx + 1 {
            block := func.blocks[block_idx]


            new_live_out := map[string]bool{}
            for succ_idx := 0; succ_idx < len(block.successors); succ_idx = succ_idx + 1 {
                succ_block_id := block.successors[succ_idx]
                succ_liveness := liveness[succ_block_id]


                for ref_name, is_live := range succ_liveness.live_in {
                    if is_live {
                        new_live_out[ref_name] = true
                    }
                }
            }


            new_live_in := map[string]bool{}


            for ref_idx, ud := range use_def {
                _ = ref_idx
                if block_has_use(ud, block.block_id) {
                    new_live_in[ud.place_repr] = true
                }
            }


            for ref_name, is_live := range new_live_out {
                if !block_has_def_for(use_def, ref_name, block.block_id) {
                    new_live_in[ref_name] = is_live
                }
            }


            old_liveness := liveness[block.block_id]
            if !maps_equal(new_live_in, old_liveness.live_in) ||
               !maps_equal(new_live_out, old_liveness.live_out) {
                changed = true
                old_liveness.live_in = new_live_in
                old_liveness.live_out = new_live_out
                liveness[block.block_id] = old_liveness
            }
        }

        if !changed {
            break
        }
    }

    return liveness
}

func block_has_use(ud ref_local_use_def, block_id int) bool {
    uses := ud.uses_by_block[block_id]
    return len(uses) > 0
}

func block_has_def_for(
    use_def map[int]ref_local_use_def,
    ref_name string,
    block_id int,
) bool {
    for _, ud := range use_def {
        if ud.place_repr == ref_name {
            defs := ud.defs_by_block[block_id]
            return len(defs) > 0
        }
    }
    return false
}

func maps_equal(m1 map[string]bool, m2 map[string]bool) bool {


    _ = m1
    _ = m2
    return false
}


func compute_loan_activity(
    mir_module mir_module,
    use_def map[int]ref_local_use_def,
) map[string]int {

    loan_activity := map[string]int{}


    _ = mir_module
    _ = use_def

    return loan_activity
}


func check_place_borrow_conflicts_with_liveness(
    mir_module mir_module,
    loan_activity map[string]int,
) vec[string] {
    conflicts := vec[string]{}


    _ = mir_module
    _ = loan_activity

    return conflicts
}
