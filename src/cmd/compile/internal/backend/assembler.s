package backend

struct assembler {
    output string[]
    labels string[]
    current_section string
    data_section string[]
    text_section string[]
}

func assembler_new() assembler {
    asm := assembler {
        output: string[](),
        labels: string[](),
        current_section: "text",
        data_section: string[](),
        text_section: string[]()
    }
    asm
}

func assembler_emit_instruction(asm* assembler, instr x86_instruction) {
    asm_text := x86_instruction_to_asm(instr)
    asm.text_section = append(asm.text_section, asm_text)
}

func assembler_emit_data(asm* assembler, label string, data string) {
    asm.data_section = append(asm.data_section, label + ":")
    asm.data_section = append(asm.data_section, "\t.quad " + data)
}

func assembler_emit_label(asm* assembler, label string) {
    asm.text_section = append(asm.text_section, label + ":")
}

func assembler_emit_function_start(asm* assembler, func_name string) {
    asm.text_section = append(asm.text_section, "")
    asm.text_section = append(asm.text_section, ".globl " + func_name)
    asm.text_section = append(asm.text_section, func_name + ":")
}

func assembler_emit_function_end(asm* assembler) {
    asm.text_section = append(asm.text_section, "")
}

func assembler_finalize(asm* assembler) string {
    output := ""
    
    output = output + ".section .data\n"
    for i := 0; i < asm.data_section.len(); i = i + 1 {
        output = output + asm.data_section[i] + "\n"
    }
    
    output = output + "\n.section .text\n"
    for i := 0; i < asm.text_section.len(); i = i + 1 {
        output = output + asm.text_section[i] + "\n"
    }
    
    output
}

func x86_instruction_to_asm(instr x86_instruction) string {
    if instr.instr_type == INSTR_MOV {
        return x86_emit_mov(instr)
    } else if instr.instr_type == INSTR_ADD {
        return x86_emit_add(instr)
    } else if instr.instr_type == INSTR_SUB {
        return x86_emit_sub(instr)
    } else if instr.instr_type == INSTR_MUL {
        return x86_emit_mul(instr)
    } else if instr.instr_type == INSTR_DIV {
        return x86_emit_div(instr)
    } else if instr.instr_type == INSTR_PUSH {
        return x86_emit_push(instr)
    } else if instr.instr_type == INSTR_POP {
        return x86_emit_pop(instr)
    } else if instr.instr_type == INSTR_CALL {
        return x86_emit_call(instr)
    } else if instr.instr_type == INSTR_RET {
        return x86_emit_ret(instr)
    } else if instr.instr_type == INSTR_CMP {
        return x86_emit_cmp(instr)
    } else if instr.instr_type == INSTR_JMP {
        return x86_emit_jmp(instr)
    }
    ""
}

func x86_emit_mov(instr x86_instruction) string {
    src := x86_operand_to_asm(instr.operand1)
    dst := x86_operand_to_asm(instr.operand2)
    "\tmovq\t" + src + ", " + dst
}

func x86_emit_add(instr x86_instruction) string {
    left := x86_operand_to_asm(instr.operand1)
    right := x86_operand_to_asm(instr.operand2)
    "\taddq\t" + left + ", " + right
}

func x86_emit_sub(instr x86_instruction) string {
    left := x86_operand_to_asm(instr.operand1)
    right := x86_operand_to_asm(instr.operand2)
    "\tsubq\t" + left + ", " + right
}

func x86_emit_mul(instr x86_instruction) string {
    left := x86_operand_to_asm(instr.operand1)
    right := x86_operand_to_asm(instr.operand2)
    "\timulq\t" + left + ", " + right
}

func x86_emit_div(instr x86_instruction) string {
    right := x86_operand_to_asm(instr.operand2)
    "\tidivq\t" + right
}

func x86_emit_push(instr x86_instruction) string {
    reg := x86_operand_to_asm(instr.operand1)
    "\tpushq\t" + reg
}

func x86_emit_pop(instr x86_instruction) string {
    reg := x86_operand_to_asm(instr.operand1)
    "\tpopq\t" + reg
}

func x86_emit_call(instr x86_instruction) string {
    target := x86_operand_to_asm(instr.operand1)
    "\tcall\t" + target
}

func x86_emit_ret(instr x86_instruction) string {
    "\tretq"
}

func x86_emit_cmp(instr x86_instruction) string {
    left := x86_operand_to_asm(instr.operand1)
    right := x86_operand_to_asm(instr.operand2)
    "\tcmpq\t" + left + ", " + right
}

func x86_emit_jmp(instr x86_instruction) string {
    target := x86_operand_to_asm(instr.operand1)
    "\tjmp\t" + target
}

func x86_operand_to_asm(op x86_operand) string {
    if op.operand_type == OPERAND_REG {
        return x86_register_name(op.reg_id)
    } else if op.operand_type == OPERAND_IMM {
        return "$" + op.imm_value
    } else if op.operand_type == OPERAND_MEM {
        return op.mem_offset as string + "(" + op.mem_base + ")"
    } else if op.operand_type == OPERAND_LABEL {
        return op.label_name
    }
    ""
}

func x86_register_name(reg_id int) string {
    if reg_id == REG_RAX {
        return "%rax"
    } else if reg_id == REG_RBX {
        return "%rbx"
    } else if reg_id == REG_RCX {
        return "%rcx"
    } else if reg_id == REG_RDX {
        return "%rdx"
    } else if reg_id == REG_RSI {
        return "%rsi"
    } else if reg_id == REG_RDI {
        return "%rdi"
    } else if reg_id == REG_R8 {
        return "%r8"
    } else if reg_id == REG_R9 {
        return "%r9"
    } else if reg_id == REG_R10 {
        return "%r10"
    } else if reg_id == REG_R11 {
        return "%r11"
    } else if reg_id == REG_R12 {
        return "%r12"
    } else if reg_id == REG_R13 {
        return "%r13"
    } else if reg_id == REG_R14 {
        return "%r14"
    } else if reg_id == REG_R15 {
        return "%r15"
    }
    ""
}
