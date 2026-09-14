package compile.internal.ir.ssa

struct ssa_value {
    int id
    string op
    int[] args
    int block_id
    int version
    option[string] type_name
}

struct ssa_phi_node {
    int id
    int target_block
    int[] incoming_blocks
    int[] incoming_values
    string type_name
}

struct ssa_block {
    int id
    string label
    ssa_value[] values
    ssa_phi_node[] phis
    int[] predecessors
    int[] successors
    int terminator_value
}

struct static_single_assignment {
    ssa_block[] blocks
    ssa_value[] all_values
    ssa_phi_node[] all_phis
    int value_counter
    int phi_counter
    int[] variable_versions
    int entry_block
    int exit_block
}

func new_ssa() static_single_assignment {
    static_single_assignment {
        blocks: ssa_block[](),
        all_values: ssa_value[](),
        all_phis: ssa_phi_node[](),
        value_counter: 0,
        phi_counter: 0,
        variable_versions: int[](),
        entry_block: 0,
        exit_block: -1
    }
}

func (ssa* static_single_assignment) create_value(string op, int[] args, int block_id, string type_name) ssa_value {
    val := ssa_value {
        id: ssa.value_counter,
        op: op,
        args: args,
        block_id: block_id,
        version: 0,
        type_name: option::some(type_name)
    }
    ssa.value_counter = ssa.value_counter + 1
    ssa.all_values.push(val)
    val
}

func (ssa* static_single_assignment) create_phi(int block_id, int[] incoming_blocks, int[] incoming_values, string type_name) ssa_phi_node {
    phi := ssa_phi_node {
        id: ssa.phi_counter,
        target_block: block_id,
        incoming_blocks: incoming_blocks,
        incoming_values: incoming_values,
        type_name: type_name
    }
    ssa.phi_counter = ssa.phi_counter + 1
    ssa.all_phis.push(phi)
    phi
}

func (ssa* static_single_assignment) add_block(int id, string label) ssa_block {
    block := ssa_block {
        id: id,
        label: label,
        values: ssa_value[](),
        phis: ssa_phi_node[](),
        predecessors: int[](),
        successors: int[](),
        terminator_value: -1
    }
    ssa.blocks.push(block)
    block
}

func (ssa* static_single_assignment) insert_phi_nodes(int[] dominance_frontier) {
    n := ssa.blocks.len()
    work_list := int[]()

    for _idx_98 := 0; _idx_98 < len(dominance_frontier); _idx_98++ {
        df_block := dominance_frontier[_idx_98]
        work_list.push(df_block)
    }

    for work_list.len() > 0 {
        block := work_list[0]
        work_list[0] = work_list[work_list.len() - 1]
        work_list = work_list[0..work_list.len() - 1]

        if block < ssa.blocks.len() {
            for _idx_108 := 0; _idx_108 < len(ssa.blocks[block].phis); _idx_108++ {
                phi := ssa.blocks[block].phis[_idx_108]
                for _idx_109 := 0; _idx_109 < len(dominance_frontier); _idx_109++ {
                    df := dominance_frontier[_idx_109]
                    already_has := false
                    for _idx_111 := 0; _idx_111 < len(ssa.blocks[df].phis); _idx_111++ {
                        existing_phi := ssa.blocks[df].phis[_idx_111]
                        if existing_phi.id == phi.id {
                            already_has = true
                            break
                        }
                    }

                    if !already_has {
                        new_phi := ssa.create_phi(df, phi.incoming_blocks, phi.incoming_values, phi.type_name)
                        ssa.blocks[df].phis.push(new_phi)

                        in_list := false
                        for _idx_123 := 0; _idx_123 < len(work_list); _idx_123++ {
                            w := work_list[_idx_123]
                            if w == df {
                                in_list = true
                                break
                            }
                        }
                        if !in_list {
                            work_list.push(df)
                        }
                    }
                }
            }
        }
    }
}

func (ssa* static_single_assignment) rename_variables() {
    stacks := int[][]()
    n := ssa.variable_versions.len()

    for i := 0; i < n; i++ {
        stacks.push(int[]())
    }

    func rename_block(int block_id) {
        if block_id >= ssa.blocks.len() {
            return
        }

        block := &ssa.blocks[block_id]

        for _idx_154 := 0; _idx_154 < len(block.phis); _idx_154++ {
            phi := block.phis[_idx_154]
            var_index := 0
            for i := 0; i < n; i++ {
                if i == var_index {
                    version := ssa.variable_versions[var_index]
                    stacks[var_index].push(version)
                    ssa.variable_versions[var_index] = version + 1
                    break
                }
            }
        }

        for _idx_166 := 0; _idx_166 < len(block.values); _idx_166++ {
            value := block.values[_idx_166]
            for _idx_167 := 0; _idx_167 < len(value.args); _idx_167++ {
                arg := value.args[_idx_167]
                var_stack := stacks[arg]
                if var_stack.len() > 0 {
                    value.args[arg] = var_stack[var_stack.len() - 1]
                }
            }

            var_index := 0
            for i := 0; i < n; i++ {
                if i == var_index {
                    version := ssa.variable_versions[var_index]
                    stacks[var_index].push(version)
                    ssa.variable_versions[var_index] = version + 1
                    break
                }
            }
        }

        for _idx_185 := 0; _idx_185 < len(block.successors); _idx_185++ {
            succ := block.successors[_idx_185]
            if succ < ssa.blocks.len() {
                for _idx_187 := 0; _idx_187 < len(ssa.blocks[succ].phis); _idx_187++ {
                    phi := ssa.blocks[succ].phis[_idx_187]
                    var_index := 0
                    for i := 0; i < n; i++ {
                        if i == var_index {
                            if stacks[var_index].len() > 0 {
                                phi.incoming_values.push(stacks[var_index][stacks[var_index].len() - 1])
                            }
                            break
                        }
                    }
                }
            }
        }

        for child := 0; child < ssa; child++.blocks.len() {
            children_ok := false
            for _idx_203 := 0; _idx_203 < len(block.successors); _idx_203++ {
                s := block.successors[_idx_203]
                if s == child {
                    children_ok = true
                    break
                }
            }
            if children_ok {
                rename_block(child)
            }
        }

        for _idx_214 := 0; _idx_214 < len(block.phis); _idx_214++ {
            phi := block.phis[_idx_214]
            var_index := 0
            for i := 0; i < n; i++ {
                if i == var_index {
                    if stacks[var_index].len() > 0 {
                        stacks[var_index][stacks[var_index].len() - 1] = stacks[var_index][stacks[var_index].len() - 1] - 1
                    }
                    break
                }
            }
        }

        for _idx_226 := 0; _idx_226 < len(block.values); _idx_226++ {
            value := block.values[_idx_226]
            var_index := 0
            for i := 0; i < n; i++ {
                if i == var_index {
                    if stacks[var_index].len() > 0 {
                        stacks[var_index][stacks[var_index].len() - 1] = stacks[var_index][stacks[var_index].len() - 1] - 1
                    }
                    break
                }
            }
        }
    }

    rename_block(ssa.entry_block)
}

func (ssa* static_single_assignment) is_phi_function(ssa_phi_node phi) bool {
    phi.incoming_values.len() > 1
}

func (ssa* static_single_assignment) get_phi_operands(ssa_phi_node phi) (int[], int[]) {
    (phi.incoming_blocks, phi.incoming_values)
}
