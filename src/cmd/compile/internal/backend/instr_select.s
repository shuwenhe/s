package backend
struct instr_selector {
    codegen_context* ctx
}

func make_instr_selector(codegen_context* ctx) instr_selector {
    is: instr_selector
    is.ctx = ctx
    is
}

func (is* instr_selector) select_const_i64(int value, int target_reg) {
    reg_name := x86_64_reg_name(target_reg)
    if value == 0 {
        instr := "\txorq\t%" + reg_name + ", %" + reg_name
        is.ctx.progs.append_prog(prog_op_xor(), instr)
    } else {
        instr := "\tmovq\t$" + to_string(value) + ", %" + reg_name
        is.ctx.progs.append_prog(prog_op_mov(), instr)
    }
}

func (is* instr_selector) select_const_i32(int value, int target_reg) {
    reg_name := x86_64_reg_name(target_reg)
    instr := "\tmovl\t$" + to_string(value) + ", %" + reg_name
    is.ctx.progs.append_prog(prog_op_mov(), instr)
}

func (is* instr_selector) select_add_i64(int left_reg, int right_reg, int result_reg) {
    if left_reg != result_reg {
        left_name := x86_64_reg_name(left_reg)
        result_name := x86_64_reg_name(result_reg)
        instr := "\tmovq\t%" + left_name + ", %" + result_name
        is.ctx.progs.append_prog(prog_op_mov(), instr)
    }
    right_name := x86_64_reg_name(right_reg)
    result_name := x86_64_reg_name(result_reg)
    instr := "\taddq\t%" + right_name + ", %" + result_name
    is.ctx.progs.append_prog(prog_op_add(), instr)
}

func (is* instr_selector) select_sub_i64(int left_reg, int right_reg, int result_reg) {
    if left_reg != result_reg {
        left_name := x86_64_reg_name(left_reg)
        result_name := x86_64_reg_name(result_reg)
        instr := "\tmovq\t%" + left_name + ", %" + result_name
        is.ctx.progs.append_prog(prog_op_mov(), instr)
    }
    right_name := x86_64_reg_name(right_reg)
    result_name := x86_64_reg_name(result_reg)
    instr := "\tsubq\t%" + right_name + ", %" + result_name
    is.ctx.progs.append_prog(prog_op_sub(), instr)
}

func (is* instr_selector) select_mul_i64(int left_reg, int right_reg, int result_reg) {
    if left_reg != result_reg {
        left_name := x86_64_reg_name(left_reg)
        result_name := x86_64_reg_name(result_reg)
        instr := "\tmovq\t%" + left_name + ", %" + result_name
        is.ctx.progs.append_prog(prog_op_mov(), instr)
    }
    right_name := x86_64_reg_name(right_reg)
    result_name := x86_64_reg_name(result_reg)
    instr := "\timulq\t%" + right_name + ", %" + result_name
    is.ctx.progs.append_prog(prog_op_mul(), instr)
}

func (is* instr_selector) select_div_i64(int left_reg, int right_reg, int result_reg) {
    if left_reg != 0 {
        left_name := x86_64_reg_name(left_reg)
        instr := "\tmovq\t%" + left_name + ", %rax"
        is.ctx.progs.append_prog(prog_op_mov(), instr)
    }
    instr := "\tcqto"
    is.ctx.progs.append_prog(prog_op_nop(), instr)
    right_name := x86_64_reg_name(right_reg)
    instr = "\tidivq\t%" + right_name
    is.ctx.progs.append_prog(prog_op_div(), instr)
    if result_reg != 0 {
        result_name := x86_64_reg_name(result_reg)
        instr := "\tmovq\t%rax, %" + result_name
        is.ctx.progs.append_prog(prog_op_mov(), instr)
    }
}

func (is* instr_selector) select_mod_i64(int left_reg, int right_reg, int result_reg) {
    if left_reg != 0 {
        left_name := x86_64_reg_name(left_reg)
        instr := "\tmovq\t%" + left_name + ", %rax"
        is.ctx.progs.append_prog(prog_op_mov(), instr)
    }
    instr := "\tcqto"
    is.ctx.progs.append_prog(prog_op_nop(), instr)
    right_name := x86_64_reg_name(right_reg)
    instr = "\tidivq\t%" + right_name
    is.ctx.progs.append_prog(prog_op_div(), instr)
    if result_reg != 2 {
        result_name := x86_64_reg_name(result_reg)
        instr := "\tmovq\t%rdx, %" + result_name
        is.ctx.progs.append_prog(prog_op_mov(), instr)
    }
}

func (is* instr_selector) select_load_i64(string addr, int target_reg) {
    reg_name := x86_64_reg_name(target_reg)
    instr := "\tmovq\t" + addr + ", %" + reg_name
    is.ctx.progs.append_prog(prog_op_load(), instr)
}

func (is* instr_selector) select_store_i64(int source_reg, string addr) {
    reg_name := x86_64_reg_name(source_reg)
    instr := "\tmovq\t%" + reg_name + ", " + addr
    is.ctx.progs.append_prog(prog_op_store(), instr)
}

func (is* instr_selector) select_call(string target, []int clobber_regs) {
    instr := "\tcall\t" + target
    is.ctx.progs.append_prog(prog_op_call(), instr)
}

func (is* instr_selector) select_return(int value_reg) {
    if value_reg != 0 {
        value_name := x86_64_reg_name(value_reg)
        instr := "\tmovq\t%" + value_name + ", %rax"
        is.ctx.progs.append_prog(prog_op_mov(), instr)
    }
    instr := "\tpop\t%rbp"
    is.ctx.progs.append_prog(prog_op_pop(), instr)
    instr = "\tretq"
    is.ctx.progs.append_prog(prog_op_ret(), instr)
}
