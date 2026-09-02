package middleend

const opt_constant_folding = 1
const opt_dead_code_elimination = 2
const opt_constant_propagation = 3
const opt_global_value_numbering = 4
const opt_licm = 5
const opt_inlining = 6

struct optimization_pass {
    pass_type int
    pass_name string
}

struct optimization_context {
    module ir_module
    cfg control_flow_graph
    dfa dataflow_analysis
    changes int
}

func run_optimization_pipeline(ir_module module*) {
    for f_idx := 0; f_idx < module.functions.len(); f_idx = f_idx + 1 {
        func := module.functions[f_idx]


        cfg := cfg_new(func)
        cfg_compute_dominators(&cfg)
        cfg_compute_post_dominators(&cfg)
        cfg_compute_dominance_frontier(&cfg)


        opt_constant_folding(&cfg)
        opt_dead_code_elimination(&cfg)
        opt_constant_propagation(&cfg)
        opt_global_value_numbering(&cfg)


    }
}

func opt_constant_folding(cfg* control_flow_graph) {
    for b_idx := 0; b_idx < cfg.blocks.len(); b_idx = b_idx + 1 {
        block := cfg.blocks[b_idx]

        for i := 0; i < block.instructions.len(); i = i + 1 {
            instr := block.instructions[i]


            if instr.instr_type == ir_instr_binop {
                left := instr.operands[0]
                right := instr.operands[1]

                if left.value_type == ir_value_const && right.value_type == ir_value_const {

                    result := opt_fold_constant(instr.opcode, left.const_value, right.const_value)


                    new_instr := ir_instr_binop(instr.opcode,
                                               ir_value_const(result, instr.result.type_info),
                                               ir_value_const("0", "int"),
                                               instr.result.type_info)
                    block.instructions[i] = new_instr
                }
            }
        }
    }
}

func opt_fold_constant(int op, string left, string right) string {

    left_val := 0
    right_val := 0

    switch op {
        case ir_op_add:
            return (left_val + right_val) as string
        case ir_op_sub:
            return (left_val - right_val) as string
        case ir_op_mul:
            return (left_val * right_val) as string
        case ir_op_div:
            if right_val != 0 {
                return (left_val / right_val) as string
            }
            return "0"
        case ir_op_mod:
            if right_val != 0 {
                return (left_val % right_val) as string
            }
            return "0"
        case ir_op_and:
            return (left_val & right_val) as string
        case ir_op_or:
            return (left_val | right_val) as string
        case ir_op_xor:
            return (left_val ^ right_val) as string
        default:
            return left
    }
}

func opt_dead_code_elimination(cfg* control_flow_graph) {

    dfa := dfa_analyze(cfg)

    for b_idx := 0; b_idx < cfg.blocks.len(); b_idx = b_idx + 1 {
        block := cfg.blocks[b_idx]

        new_instrs := ir_instruction[]()

        for i := 0; i < block.instructions.len(); i = i + 1 {
            instr := block.instructions[i]


            if instr.instr_type == ir_instr_store ||
               instr.instr_type == ir_instr_call ||
               instr.instr_type == ir_instr_return {
                new_instrs = append(new_instrs, instr)
                continue
            }


            is_used := 0
            for j := i + 1; j < block.instructions.len(); j = j + 1 {
                next_instr := block.instructions[j]
                for k := 0; k < next_instr.operands.len(); k = k + 1 {
                    if next_instr.operands[k].value_id == instr.result.value_id {
                        is_used = 1
                    }
                }
            }


            if is_used == 0 {
                for l := 0; l < dfa.liveness.len(); l = l + 1 {
                    if dfa.liveness[l].block_id == block.block_id {
                        if int_set_contains(dfa.liveness[l].live_out, instr.result.value_id) != 0 {
                            is_used = 1
                        }
                    }
                }
            }


            if is_used != 0 {
                new_instrs = append(new_instrs, instr)
            }
        }

        block.instructions = new_instrs
    }
}

func opt_constant_propagation(cfg* control_flow_graph) {
    constants := make_string_value_map()

    for b_idx := 0; b_idx < cfg.blocks.len(); b_idx = b_idx + 1 {
        block := cfg.blocks[b_idx]

        for i := 0; i < block.instructions.len(); i = i + 1 {
            instr := block.instructions[i]


            if instr.result.value_type == ir_value_var &&
               instr.operands.len() == 1 &&
               instr.operands[0].value_type == ir_value_const {

                constants[instr.result.var_name] = instr.operands[0]
            }


            for j := 0; j < instr.operands.len(); j = j + 1 {
                if instr.operands[j].value_type == ir_value_var {

                    if constants[instr.operands[j].var_name].value_type == ir_value_const {
                        instr.operands[j] = constants[instr.operands[j].var_name]
                    }
                }
            }
        }
    }
}

func opt_global_value_numbering(cfg* control_flow_graph) {
    value_map := make_string_instruction_map()

    for b_idx := 0; b_idx < cfg.blocks.len(); b_idx = b_idx + 1 {
        block := cfg.blocks[b_idx]

        new_instrs := ir_instruction[]()

        for i := 0; i < block.instructions.len(); i = i + 1 {
            instr := block.instructions[i]


            signature := opt_compute_instruction_signature(instr)


            if signature != "" && value_map[signature].result.value_id != 0 {

                prev_result := value_map[signature].result


                new_instrs = append(new_instrs, instr)
            } else {
                new_instrs = append(new_instrs, instr)
                if signature != "" {
                    value_map[signature] = instr
                }
            }
        }

        block.instructions = new_instrs
    }
}

func opt_compute_instruction_signature(ir_instruction instr) string {

    sig := ""

    if instr.instr_type == ir_instr_binop {
        sig = "binop_" + instr.opcode as string + "_"
        for i := 0; i < instr.operands.len(); i = i + 1 {
            sig = sig + instr.operands[i].const_value + "_"
        }
    }

    sig
}

func make_string_value_map() string[] {
    string[]()
}

func make_string_instruction_map() ir_instruction[] {
    ir_instruction[]()
}

func opt_licm(cfg* control_flow_graph, loop_info[] loops) {
    for loop_idx := 0; loop_idx < loops.len(); loop_idx = loop_idx + 1 {
        loop := loops[loop_idx]


        invariant_instrs := ir_instruction[]()

        for b_idx := 0; b_idx < cfg.blocks.len(); b_idx = b_idx + 1 {
            block := cfg.blocks[b_idx]


            is_in_loop := 0
            for l_idx := 0; l_idx < loop.body_blocks.len(); l_idx = l_idx + 1 {
                if loop.body_blocks[l_idx] == block.block_id {
                    is_in_loop = 1
                }
            }

            if is_in_loop == 0 {
                continue
            }


            for i := 0; i < block.instructions.len(); i = i + 1 {
                instr := block.instructions[i]


                is_invariant := 1
                for j := 0; j < instr.operands.len(); j = j + 1 {
                    operand := instr.operands[j]
                    if operand.value_type == ir_value_var {

                        is_invariant = 0
                    }
                }

                if is_invariant != 0 {
                    invariant_instrs = append(invariant_instrs, instr)
                }
            }
        }


        if invariant_instrs.len() > 0 && loop.header_id >= 0 {
            header_block := cfg.blocks[loop.header_id]
            for i := 0; i < invariant_instrs.len(); i = i + 1 {
                header_block.instructions = append(header_block.instructions, invariant_instrs[i])
            }
        }
    }
}

