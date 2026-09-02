package backend

const FRAME_ARG_AREA = 1
const FRAME_LOCAL_AREA = 2
const FRAME_SPILL_AREA = 3

struct stack_slot {
    slot_id int
    offset int
    size int
    slot_type int
}

struct stack_frame {
    func_name string
    arg_slots stack_slot[]
    local_slots stack_slot[]
    spill_slots stack_slot[]
    stack_size int
    alignment int
}

func stack_frame_new(func_name string) stack_frame {
    frame := stack_frame {
        func_name: func_name,
        arg_slots: stack_slot[](),
        local_slots: stack_slot[](),
        spill_slots: stack_slot[](),
        stack_size: 0,
        alignment: 16
    }
    frame
}

func stack_frame_add_arg(frame* stack_frame, slot_id int, size int) int {
    offset := frame.arg_slots.len() * 8
    
    slot := stack_slot {
        slot_id: slot_id,
        offset: offset,
        size: size,
        slot_type: FRAME_ARG_AREA
    }
    
    frame.arg_slots = append(frame.arg_slots, slot)
    offset
}

func stack_frame_add_local(frame* stack_frame, slot_id int, size int) int {
    offset := -(frame.local_slots.len() + 1) * 8
    
    slot := stack_slot {
        slot_id: slot_id,
        offset: offset,
        size: size,
        slot_type: FRAME_LOCAL_AREA
    }
    
    frame.local_slots = append(frame.local_slots, slot)
    offset
}

func stack_frame_add_spill(frame* stack_frame, slot_id int, size int) int {
    base_offset := -(frame.local_slots.len() + 1) * 8
    spill_offset := base_offset - (frame.spill_slots.len() + 1) * 8
    
    slot := stack_slot {
        slot_id: slot_id,
        offset: spill_offset,
        size: size,
        slot_type: FRAME_SPILL_AREA
    }
    
    frame.spill_slots = append(frame.spill_slots, slot)
    spill_offset
}

func stack_frame_compute_size(frame* stack_frame) int {
    local_size := frame.local_slots.len() * 8
    spill_size := frame.spill_slots.len() * 8
    return_addr_size := 8
    
    total := local_size + spill_size + return_addr_size
    
    if total % frame.alignment != 0 {
        total = total + (frame.alignment - (total % frame.alignment))
    }
    
    frame.stack_size = total
    total
}

func stack_frame_get_slot_offset(frame stack_frame, slot_id int) int {
    for i := 0; i < frame.local_slots.len(); i = i + 1 {
        if frame.local_slots[i].slot_id == slot_id {
            return frame.local_slots[i].offset
        }
    }
    
    for i := 0; i < frame.spill_slots.len(); i = i + 1 {
        if frame.spill_slots[i].slot_id == slot_id {
            return frame.spill_slots[i].offset
        }
    }
    
    0
}

func stack_frame_emit_prologue(frame stack_frame, ctx* codegen_context) {
    push_instr := x86_instruction {
        instr_type: INSTR_PUSH,
        operand1: x86_operand { operand_type: OPERAND_REG, reg_id: REG_RAX },
        operand2: x86_operand { operand_type: 0 },
        operand3: x86_operand { operand_type: 0 }
    }
    
    ctx.instrs = append(ctx.instrs, push_instr)
    
    if frame.stack_size > 0 {
        sub_instr := x86_instruction {
            instr_type: INSTR_SUB,
            operand1: x86_operand { operand_type: OPERAND_REG, reg_id: REG_RSP },
            operand2: x86_operand { operand_type: OPERAND_IMM, imm_value: frame.stack_size as string },
            operand3: x86_operand { operand_type: 0 }
        }
        
        ctx.instrs = append(ctx.instrs, sub_instr)
    }
}

func stack_frame_emit_epilogue(frame stack_frame, ctx* codegen_context) {
    if frame.stack_size > 0 {
        add_instr := x86_instruction {
            instr_type: INSTR_ADD,
            operand1: x86_operand { operand_type: OPERAND_REG, reg_id: REG_RSP },
            operand2: x86_operand { operand_type: OPERAND_IMM, imm_value: frame.stack_size as string },
            operand3: x86_operand { operand_type: 0 }
        }
        
        ctx.instrs = append(ctx.instrs, add_instr)
    }
    
    pop_instr := x86_instruction {
        instr_type: INSTR_POP,
        operand1: x86_operand { operand_type: OPERAND_REG, reg_id: REG_RAX },
        operand2: x86_operand { operand_type: 0 },
        operand3: x86_operand { operand_type: 0 }
    }
    
    ctx.instrs = append(ctx.instrs, pop_instr)
}

struct codegen_context {
    module ir_module
    instrs x86_instruction[]
    labels string[]
    current_func ir_function
}
