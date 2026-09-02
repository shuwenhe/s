package backend

func test_instruction_selector_simple_mov() {
    ir_func := ir_function {
        name: "test_mov",
        blocks: ir_basicblock[](),
        params: ir_value[](),
        return_type: "int"
    }
    
    block := ir_basicblock {
        block_id: 0,
        instructions: ir_instruction[](),
        successors: int[](),
        predecessors: int[]()
    }
    
    mov_instr := ir_instruction {
        instr_type: 1,
        opcode: 0,
        result: ir_value { value_id: 1, value_type: 1, var_name: "tmp1" },
        operands: ir_value[]()
    }
    
    block.instructions = append(block.instructions, mov_instr)
    ir_func.blocks = append(ir_func.blocks, block)
    
    selector := instruction_selector_new(ir_func)
    instruction_selector_select(&selector)
}

func test_register_allocator_allocation() {
    allocator := register_allocator_new()
    
    instr1 := x86_instruction { instr_type: instr_mov }
    instr2 := x86_instruction { instr_type: instr_add }
    instr3 := x86_instruction { instr_type: instr_sub }
    
    instrs := x86_instruction[]()
    instrs = append(instrs, instr1)
    instrs = append(instrs, instr2)
    instrs = append(instrs, instr3)
    
    register_allocator_build_intervals(&allocator, instrs)
    register_allocator_build_interference_graph(&allocator)
    register_allocator_allocate(&allocator)
}

func test_stack_frame_allocation() {
    frame := stack_frame_new("test_func")
    
    arg_offset := stack_frame_add_arg(&frame, 0, 8)
    local_offset := stack_frame_add_local(&frame, 1, 8)
    spill_offset := stack_frame_add_spill(&frame, 2, 8)
    
    stack_size := stack_frame_compute_size(&frame)
}

func test_assembler_emission() {
    asm := assembler_new()
    
    mov_instr := x86_instruction {
        instr_type: instr_mov,
        operand1: x86_operand { operand_type: operand_reg, reg_id: reg_rax },
        operand2: x86_operand { operand_type: operand_reg, reg_id: reg_rbx },
        operand3: x86_operand { operand_type: 0 }
    }
    
    assembler_emit_function_start(&asm, "test_func")
    assembler_emit_instruction(&asm, mov_instr)
    assembler_emit_function_end(&asm)
    
    output := assembler_finalize(&asm)
}

func test_x86_operand_to_asm() {
    reg_op := x86_operand { operand_type: operand_reg, reg_id: reg_rax }
    imm_op := x86_operand { operand_type: operand_imm, imm_value: "42" }
    mem_op := x86_operand { operand_type: operand_mem, mem_base: "rbp", mem_offset: -8 }
    label_op := x86_operand { operand_type: operand_label, label_name: "loop_start" }
    
    reg_asm := x86_operand_to_asm(reg_op)
    imm_asm := x86_operand_to_asm(imm_op)
    mem_asm := x86_operand_to_asm(mem_op)
    label_asm := x86_operand_to_asm(label_op)
}
