package backend

struct direct_code_generator {
    prog_list* main_code
    prog_list* data_section
    instr_selector* selector
    reg_alloc_state* alloc
}

func make_direct_code_generator() direct_code_generator {
    gen: direct_code_generator
    gen.main_code = &make_prog_list()
    gen.data_section = &make_prog_list()
    gen.alloc = &make_reg_alloc_state()
    gen
}

func (gen* direct_code_generator) generate_function_prologue(string func_name, int stack_size) {
    gen.main_code.append_prog(20, ".globl " + func_name)
    gen.main_code.append_prog(20, ".type " + func_name + ", @function")
    gen.main_code.append_prog(20, func_name + ":")
    
    gen.main_code.append_prog(prog_op_push(), "\tpushq\t%rbp")
    gen.main_code.append_prog(prog_op_mov(), "\tmovq\t%rsp, %rbp")
    
    if stack_size > 0 {
        instr := "\tsubq\t$" + to_string(stack_size) + ", %rsp"
        gen.main_code.append_prog(prog_op_sub(), instr)
    }
}

func (gen* direct_code_generator) generate_function_epilogue() {
    gen.main_code.append_prog(prog_op_pop(), "\tpopq\t%rbp")
    gen.main_code.append_prog(prog_op_ret(), "\tretq")
}

func (gen* direct_code_generator) generate_text_section() string {
    result := ".section\t.text\n"
    p := gen.main_code.first()
    while p != nil {
        result = result + p.as_string + "\n"
        p = p.next
    }
    result
}

func (gen* direct_code_generator) generate_data_section() string {
    result := ".section\t.data\n"
    p := gen.data_section.first()
    while p != nil {
        result = result + p.as_string + "\n"
        p = p.next
    }
    result
}

func (gen* direct_code_generator) generate_rodata_section() string {
    result := ".section\t.rodata\n"
    result
}

func (gen* direct_code_generator) generate_symtab() string {
    result := ".section\t.symtab\n"
    result
}

func (gen* direct_code_generator) generate_strtab() string {
    result := ".section\t.strtab\n"
    result
}

func (gen* direct_code_generator) generate_asm() string {
    asm := ""
    asm = asm + ".intel_syntax noprefix\n"
    asm = asm + gen.generate_text_section()
    asm = asm + "\n"
    asm = asm + gen.generate_data_section()
    asm = asm + "\n"
    asm = asm + gen.generate_rodata_section()
    asm
}

func (gen* direct_code_generator) emit_const_i64(int value, int reg) {
    reg_name := x86_64_reg_name(reg)
    if value == 0 {
        instr := "\txorq\t%" + reg_name + ", %" + reg_name
        gen.main_code.append_prog(prog_op_xor(), instr)
    } else {
        instr := "\tmovq\t$" + to_string(value) + ", %" + reg_name
        gen.main_code.append_prog(prog_op_mov(), instr)
    }
}

func (gen* direct_code_generator) emit_add_i64(int lhs_reg, int rhs_reg, int result_reg) {
    if lhs_reg != result_reg {
        lhs_name := x86_64_reg_name(lhs_reg)
        result_name := x86_64_reg_name(result_reg)
        instr := "\tmovq\t%" + lhs_name + ", %" + result_name
        gen.main_code.append_prog(prog_op_mov(), instr)
    }
    
    rhs_name := x86_64_reg_name(rhs_reg)
    result_name := x86_64_reg_name(result_reg)
    instr := "\taddq\t%" + rhs_name + ", %" + result_name
    gen.main_code.append_prog(prog_op_add(), instr)
}

func (gen* direct_code_generator) get_asm() string {
    gen.generate_asm()
}
