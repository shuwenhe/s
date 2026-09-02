package backend

const INSTR_MOV = 1
const INSTR_ADD = 2
const INSTR_SUB = 3
const INSTR_MUL = 4
const INSTR_DIV = 5
const INSTR_MOD = 6
const INSTR_AND = 7
const INSTR_OR = 8
const INSTR_XOR = 9
const INSTR_SHL = 10
const INSTR_SHR = 11
const INSTR_CMP = 12
const INSTR_JMP = 13
const INSTR_JZ = 14
const INSTR_JNZ = 15
const INSTR_CALL = 16
const INSTR_RET = 17
const INSTR_PUSH = 18
const INSTR_POP = 19
const INSTR_LOAD = 20
const INSTR_STORE = 21

const OPERAND_REG = 1
const OPERAND_IMM = 2
const OPERAND_MEM = 3
const OPERAND_LABEL = 4

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

func instruction_selector_new(ir_func ir_function) instruction_selector {
    selector := instruction_selector {
        ir_func: ir_func,
        x86_instrs: x86_instruction[](),
        var_to_reg_map: string[](),
        stack_offset: 0
    }
    selector
}

func instruction_selector_select(selector* instruction_selector) {
    for b_idx := 0; b_idx < selector.ir_func.blocks.len(); b_idx = b_idx + 1 {
        block := selector.ir_func.blocks[b_idx]
        
        for i := 0; i < block.instructions.len(); i = i + 1 {
            instr := block.instructions[i]
            instruction_selector_process_instruction(selector, instr)
        }
    }
}

func instruction_selector_process_instruction(selector* instruction_selector, instr ir_instruction) {
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

func selector_handle_load(selector* instruction_selector, instr ir_instruction) {
    src_reg := allocate_register(selector, instr.operands[0].var_name)
    dst_reg := allocate_register(selector, instr.result.var_name)
    
    mov_instr := x86_instruction {
        instr_type: INSTR_MOV,
        operand1: x86_operand { operand_type: OPERAND_REG, reg_id: src_reg },
        operand2: x86_operand { operand_type: OPERAND_REG, reg_id: dst_reg },
        operand3: x86_operand { operand_type: 0 }
    }
    
    selector.x86_instrs = append(selector.x86_instrs, mov_instr)
}

func selector_handle_store(selector* instruction_selector, instr ir_instruction) {
    src_reg := allocate_register(selector, instr.operands[0].var_name)
    dst_reg := allocate_register(selector, instr.result.var_name)
    
    mov_instr := x86_instruction {
        instr_type: INSTR_MOV,
        operand1: x86_operand { operand_type: OPERAND_REG, reg_id: src_reg },
        operand2: x86_operand { operand_type: OPERAND_REG, reg_id: dst_reg },
        operand3: x86_operand { operand_type: 0 }
    }
    
    selector.x86_instrs = append(selector.x86_instrs, mov_instr)
}

func selector_handle_binop(selector* instruction_selector, instr ir_instruction) {
    left_reg := allocate_register(selector, instr.operands[0].var_name)
    right_reg := allocate_register(selector, instr.operands[1].var_name)
    result_reg := allocate_register(selector, instr.result.var_name)
    
    instr_type := ir_opcode_to_x86(instr.opcode)
    
    binop_instr := x86_instruction {
        instr_type: instr_type,
        operand1: x86_operand { operand_type: OPERAND_REG, reg_id: left_reg },
        operand2: x86_operand { operand_type: OPERAND_REG, reg_id: right_reg },
        operand3: x86_operand { operand_type: OPERAND_REG, reg_id: result_reg }
    }
    
    selector.x86_instrs = append(selector.x86_instrs, binop_instr)
}

func selector_handle_unop(selector* instruction_selector, instr ir_instruction) {
    operand_reg := allocate_register(selector, instr.operands[0].var_name)
    result_reg := allocate_register(selector, instr.result.var_name)
    
    mov_instr := x86_instruction {
        instr_type: INSTR_MOV,
        operand1: x86_operand { operand_type: OPERAND_REG, reg_id: operand_reg },
        operand2: x86_operand { operand_type: OPERAND_REG, reg_id: result_reg },
        operand3: x86_operand { operand_type: 0 }
    }
    
    selector.x86_instrs = append(selector.x86_instrs, mov_instr)
}

func selector_handle_call(selector* instruction_selector, instr ir_instruction) {
    call_instr := x86_instruction {
        instr_type: INSTR_CALL,
        operand1: x86_operand { operand_type: OPERAND_LABEL, label_name: instr.operands[0].const_value },
        operand2: x86_operand { operand_type: 0 },
        operand3: x86_operand { operand_type: 0 }
    }
    
    selector.x86_instrs = append(selector.x86_instrs, call_instr)
}

func selector_handle_return(selector* instruction_selector, instr ir_instruction) {
    ret_instr := x86_instruction {
        instr_type: INSTR_RET,
        operand1: x86_operand { operand_type: 0 },
        operand2: x86_operand { operand_type: 0 },
        operand3: x86_operand { operand_type: 0 }
    }
    
    selector.x86_instrs = append(selector.x86_instrs, ret_instr)
}

func allocate_register(selector* instruction_selector, var_name string) int {
    for i := 0; i < selector.var_to_reg_map.len(); i = i + 1 {
        if selector.var_to_reg_map[i] == var_name {
            return i
        }
    }
    
    reg_id := selector.var_to_reg_map.len()
    selector.var_to_reg_map = append(selector.var_to_reg_map, var_name)
    reg_id
}

func ir_opcode_to_x86(opcode int) int {
    switch opcode {
        case 1:
            return INSTR_ADD
        case 2:
            return INSTR_SUB
        case 3:
            return INSTR_MUL
        case 4:
            return INSTR_DIV
        default:
            return INSTR_MOV
    }
}
