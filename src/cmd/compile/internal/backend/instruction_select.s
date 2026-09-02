package backend

const instr_mov = 1
const instr_add = 2
const instr_sub = 3
const instr_mul = 4
const instr_div = 5
const instr_mod = 6
const instr_and = 7
const instr_or = 8
const instr_xor = 9
const instr_shl = 10
const instr_shr = 11
const instr_cmp = 12
const instr_jmp = 13
const instr_jz = 14
const instr_jnz = 15
const instr_call = 16
const instr_ret = 17
const instr_push = 18
const instr_pop = 19
const instr_load = 20
const instr_store = 21

const operand_reg = 1
const operand_imm = 2
const operand_mem = 3
const operand_label = 4

struct x86_operand {
    operand_type int
    reg_id int
    imm_value string
    mem_base string
    mem_offset int
    label_name string
}

struct x86_instruction {
    instr_type int
    operand1 x86_operand
    operand2 x86_operand
    operand3 x86_operand
}

struct instruction_selector {
    ir_func ir_function
    x86_instrs x86_instruction[]
    var_to_reg_map string[]
    stack_offset int
}

func instruction_selector_new(ir_function ir_func) instruction_selector {
    selector := instruction_selector {
        ir_func: ir_func,
        x86_instrs: x86_instruction[](),
        var_to_reg_map: string[](),
        stack_offset: 0
    }
    selector
}

func instruction_selector_select(instruction_selector selector*) {
    for b_idx := 0; b_idx < selector.ir_func.blocks.len(); b_idx = b_idx + 1 {
        block := selector.ir_func.blocks[b_idx]
        
        for i := 0; i < block.instructions.len(); i = i + 1 {
            instr := block.instructions[i]
            instruction_selector_process_instruction(selector, instr)
        }
    }
}

func instruction_selector_process_instruction(instruction_selector selector*, ir_instruction instr) {
    if instr.instr_type == 1 {
        selector_handle_load(selector, instr)
    } else if instr.instr_type == 2 {
        selector_handle_store(selector, instr)
    } else if instr.instr_type == 3 {
        selector_handle_binop(selector, instr)
    } else if instr.instr_type == 4 {
        selector_handle_unop(selector, instr)
    } else if instr.instr_type == 5 {
        selector_handle_call(selector, instr)
    } else if instr.instr_type == 6 {
        selector_handle_return(selector, instr)
    }
}

func selector_handle_load(instruction_selector selector*, ir_instruction instr) {
    src_reg := allocate_register(selector, instr.operands[0].var_name)
    dst_reg := allocate_register(selector, instr.result.var_name)
    
    mov_instr := x86_instruction {
        instr_type: instr_mov,
        operand1: x86_operand { operand_type: operand_reg, reg_id: src_reg },
        operand2: x86_operand { operand_type: operand_reg, reg_id: dst_reg },
        operand3: x86_operand { operand_type: 0 }
    }
    
    selector.x86_instrs = append(selector.x86_instrs, mov_instr)
}

func selector_handle_store(instruction_selector selector*, ir_instruction instr) {
    src_reg := allocate_register(selector, instr.operands[0].var_name)
    dst_reg := allocate_register(selector, instr.result.var_name)
    
    mov_instr := x86_instruction {
        instr_type: instr_mov,
        operand1: x86_operand { operand_type: operand_reg, reg_id: src_reg },
        operand2: x86_operand { operand_type: operand_reg, reg_id: dst_reg },
        operand3: x86_operand { operand_type: 0 }
    }
    
    selector.x86_instrs = append(selector.x86_instrs, mov_instr)
}

func selector_handle_binop(instruction_selector selector*, ir_instruction instr) {
    left_reg := allocate_register(selector, instr.operands[0].var_name)
    right_reg := allocate_register(selector, instr.operands[1].var_name)
    result_reg := allocate_register(selector, instr.result.var_name)
    
    instr_type := ir_opcode_to_x86(instr.opcode)
    
    binop_instr := x86_instruction {
        instr_type: instr_type,
        operand1: x86_operand { operand_type: operand_reg, reg_id: left_reg },
        operand2: x86_operand { operand_type: operand_reg, reg_id: right_reg },
        operand3: x86_operand { operand_type: operand_reg, reg_id: result_reg }
    }
    
    selector.x86_instrs = append(selector.x86_instrs, binop_instr)
}

func selector_handle_unop(instruction_selector selector*, ir_instruction instr) {
    operand_reg := allocate_register(selector, instr.operands[0].var_name)
    result_reg := allocate_register(selector, instr.result.var_name)
    
    mov_instr := x86_instruction {
        instr_type: instr_mov,
        operand1: x86_operand { operand_type: operand_reg, reg_id: operand_reg },
        operand2: x86_operand { operand_type: operand_reg, reg_id: result_reg },
        operand3: x86_operand { operand_type: 0 }
    }
    
    selector.x86_instrs = append(selector.x86_instrs, mov_instr)
}

func selector_handle_call(instruction_selector selector*, ir_instruction instr) {
    call_instr := x86_instruction {
        instr_type: instr_call,
        operand1: x86_operand { operand_type: operand_label, label_name: instr.operands[0].const_value },
        operand2: x86_operand { operand_type: 0 },
        operand3: x86_operand { operand_type: 0 }
    }
    
    selector.x86_instrs = append(selector.x86_instrs, call_instr)
}

func selector_handle_return(instruction_selector selector*, ir_instruction instr) {
    ret_instr := x86_instruction {
        instr_type: instr_ret,
        operand1: x86_operand { operand_type: 0 },
        operand2: x86_operand { operand_type: 0 },
        operand3: x86_operand { operand_type: 0 }
    }
    
    selector.x86_instrs = append(selector.x86_instrs, ret_instr)
}

func allocate_register(instruction_selector selector*, string var_name) int {
    for i := 0; i < selector.var_to_reg_map.len(); i = i + 1 {
        if selector.var_to_reg_map[i] == var_name {
            return i
        }
    }
    
    reg_id := selector.var_to_reg_map.len()
    selector.var_to_reg_map = append(selector.var_to_reg_map, var_name)
    reg_id
}

func ir_opcode_to_x86(int opcode) int {
    switch opcode {
        case 1:
            return instr_add
        case 2:
            return instr_sub
        case 3:
            return instr_mul
        case 4:
            return instr_div
        default:
            return instr_mov
    }
}
