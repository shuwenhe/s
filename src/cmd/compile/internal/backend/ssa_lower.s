package backend
struct ssa_to_machine {
    codegen_context* ctx
    ssa_function* func
    prog_list* progs
}

func make_ssa_to_machine(codegen_context* ctx, ssa_function* func) ssa_to_machine {
    tm: ssa_to_machine
    tm.ctx = ctx
    tm.func = func
    tm.progs = &make_prog_list()
    tm
}

func (tm* ssa_to_machine) lower_block(ssa_block* b) {
    i := 0
    while i < len(b.values) {
        value_id := b.values[i]
        tm.lower_value(value_id)
        i = i + 1
    }
}

func (tm* ssa_to_machine) lower_value(int value_id) {
}

func (tm* ssa_to_machine) emit_alloca(int size) string {
    offset := tm.ctx.alloc_state.next_stack_offset - size
    tm.ctx.alloc_state.next_stack_offset = offset
    "-" + to_string(-offset) + "(%rbp)"
}

func (tm* ssa_to_machine) emit_load(string addr, int reg) {
    reg_name := x86_64_reg_name(reg)
    instr := "\tmovq\t" + addr + ", %" + reg_name
    tm.progs.append_prog(prog_op_load(), instr)
}

func (tm* ssa_to_machine) emit_store(int reg, string addr) {
    reg_name := x86_64_reg_name(reg)
    instr := "\tmovq\t%" + reg_name + ", " + addr
    tm.progs.append_prog(prog_op_store(), instr)
}

func (tm* ssa_to_machine) emit_binary_op(string op, int left_reg, int right_reg, int result_reg) {
    left_name := x86_64_reg_name(left_reg)
    right_name := x86_64_reg_name(right_reg)
    result_name := x86_64_reg_name(result_reg)
    if left_reg != result_reg {
        instr := "\tmovq\t%" + left_name + ", %" + result_name
        tm.progs.append_prog(prog_op_mov(), instr)
    }
    instr := ""
    switch op {
        case "add" : instr = "\taddq\t%" + right_name + ", %" + result_name,
        case "sub" : instr = "\tsubq\t%" + right_name + ", %" + result_name,
        case "mul" : instr = "\timulq\t%" + right_name + ", %" + result_name,
        case "div" : instr = "\tidivq\t%" + right_name,
        case "and" : instr = "\tandq\t%" + right_name + ", %" + result_name,
        case "or" : instr = "\torq\t%" + right_name + ", %" + result_name,
        case "xor" : instr = "\txorq\t%" + right_name + ", %" + result_name,
        default : instr = "\tnop"
    }
    tm.progs.append_prog(1, instr)
}

func (tm* ssa_to_machine) emit_comparison(string cond, int left_reg, int right_reg) int {
    left_name := x86_64_reg_name(left_reg)
    right_name := x86_64_reg_name(right_reg)
    cmp_instr := "\tcmpq\t%" + right_name + ", %" + left_name
    tm.progs.append_prog(prog_op_cmp(), cmp_instr)
    result_reg := 0
    set_instr := ""
    switch cond {
        case "eq" : set_instr = "\tsete\t%al",
        case "ne" : set_instr = "\tsetne\t%al",
        case "lt" : set_instr = "\tsetl\t%al",
        case "le" : set_instr = "\tsetle\t%al",
        case "gt" : set_instr = "\tsetg\t%al",
        case "ge" : set_instr = "\tsetge\t%al",
        default : set_instr = "\tnop"
    }
    tm.progs.append_prog(20, set_instr)
    movz_instr := "\tmovzbl\t%al, %" + x86_64_reg_name(result_reg)
    tm.progs.append_prog(prog_op_mov(), movz_instr)
    result_reg
}

func (tm* ssa_to_machine) generate() prog_list {
    tm.ctx.current_func = tm.func.name
    tm.ctx.emit_prologue()
    i := 0
    while i < tm.func.block_count {
        tm.lower_block(&tm.func.blocks[i])
        i = i + 1
    }
    tm.ctx.emit_epilogue()
    tm.func.stack_size = tm.ctx.alloc_state.get_stack_size()
    *tm.progs
}
