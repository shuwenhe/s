package backend

struct assembler {
    output []string
    labels []string
    current_section string
    data_section []string
    text_section []string
}

func assembler_new() assembler {
    asm := assembler {
        output: []string(),
        labels: []string(),
        current_section: "text",
        data_section: []string(),
        text_section: []string()
    }
    asm
}

func assembler_emit_instruction(asm* assembler, x86_instruction instr) {
    asm_text := x86_instruction_to_asm(instr)
    asm.text_section = append(asm.text_section, asm_text)
}

func assembler_emit_data(asm* assembler, string label, string data) {
    asm.data_section = append(asm.data_section, label + ":")
    asm.data_section = append(asm.data_section, "\t.quad " + data)
}

func assembler_emit_label(asm* assembler, string label) {
    asm.text_section = append(asm.text_section, label + ":")
}

func assembler_emit_function_start(asm* assembler, string func_name) {
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

func x86_instruction_to_asm(x86_instruction instr) string {
    if instr.instr_type == instr_mov {
        return x86_emit_mov(instr)
    } else if instr.instr_type == instr_add {
        return x86_emit_add(instr)
    } else if instr.instr_type == instr_sub {
        return x86_emit_sub(instr)
    } else if instr.instr_type == instr_mul {
        return x86_emit_mul(instr)
    } else if instr.instr_type == instr_div {
        return x86_emit_div(instr)
    } else if instr.instr_type == instr_push {
        return x86_emit_push(instr)
    } else if instr.instr_type == instr_pop {
        return x86_emit_pop(instr)
    } else if instr.instr_type == instr_call {
        return x86_emit_call(instr)
    } else if instr.instr_type == instr_ret {
        return x86_emit_ret(instr)
    } else if instr.instr_type == instr_cmp {
        return x86_emit_cmp(instr)
    } else if instr.instr_type == instr_jmp {
        return x86_emit_jmp(instr)
    }
    ""
}

func x86_emit_mov(x86_instruction instr) string {
    src := x86_operand_to_asm(instr.operand1)
    dst := x86_operand_to_asm(instr.operand2)
    "\tmovq\t" + src + ", " + dst
}

func x86_emit_add(x86_instruction instr) string {
    left := x86_operand_to_asm(instr.operand1)
    right := x86_operand_to_asm(instr.operand2)
    "\taddq\t" + left + ", " + right
}

func x86_emit_sub(x86_instruction instr) string {
    left := x86_operand_to_asm(instr.operand1)
    right := x86_operand_to_asm(instr.operand2)
    "\tsubq\t" + left + ", " + right
}

func x86_emit_mul(x86_instruction instr) string {
    left := x86_operand_to_asm(instr.operand1)
    right := x86_operand_to_asm(instr.operand2)
    "\timulq\t" + left + ", " + right
}

func x86_emit_div(x86_instruction instr) string {
    right := x86_operand_to_asm(instr.operand2)
    "\tidivq\t" + right
}

func x86_emit_push(x86_instruction instr) string {
    reg := x86_operand_to_asm(instr.operand1)
    "\tpushq\t" + reg
}

func x86_emit_pop(x86_instruction instr) string {
    reg := x86_operand_to_asm(instr.operand1)
    "\tpopq\t" + reg
}

func x86_emit_call(x86_instruction instr) string {
    target := x86_operand_to_asm(instr.operand1)
    "\tcall\t" + target
}

func x86_emit_ret(x86_instruction instr) string {
    "\tretq"
}

func x86_emit_cmp(x86_instruction instr) string {
    left := x86_operand_to_asm(instr.operand1)
    right := x86_operand_to_asm(instr.operand2)
    "\tcmpq\t" + left + ", " + right
}

func x86_emit_jmp(x86_instruction instr) string {
    target := x86_operand_to_asm(instr.operand1)
    "\tjmp\t" + target
}

func x86_operand_to_asm(x86_operand op) string {
    if op.operand_type == operand_reg {
        return x86_register_name(op.reg_id)
    } else if op.operand_type == operand_imm {
        return "$" + op.imm_value
    } else if op.operand_type == operand_mem {
        return op.mem_offset as string + "(" + op.mem_base + ")"
    } else if op.operand_type == operand_label {
        return op.label_name
    }
    ""
}

func x86_register_name(int reg_id) string {
    if reg_id == reg_rax {
        return "%rax"
    } else if reg_id == reg_rbx {
        return "%rbx"
    } else if reg_id == reg_rcx {
        return "%rcx"
    } else if reg_id == reg_rdx {
        return "%rdx"
    } else if reg_id == reg_rsi {
        return "%rsi"
    } else if reg_id == reg_rdi {
        return "%rdi"
    } else if reg_id == reg_r8 {
        return "%r8"
    } else if reg_id == reg_r9 {
        return "%r9"
    } else if reg_id == reg_r10 {
        return "%r10"
    } else if reg_id == reg_r11 {
        return "%r11"
    } else if reg_id == reg_r12 {
        return "%r12"
    } else if reg_id == reg_r13 {
        return "%r13"
    } else if reg_id == reg_r14 {
        return "%r14"
    } else if reg_id == reg_r15 {
        return "%r15"
    }
    ""
}
