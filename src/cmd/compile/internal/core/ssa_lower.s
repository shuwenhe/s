package compile.internal.core
struct ssa_to_machine {
    codegen_context* ctx
    ssa_function* function_data
    prog_list* progs
}

func make_ssa_to_machine(ctx* codegen_context, function_data* ssa_function) ssa_to_machine {
    tm := ssa_to_machine {
        ctx: ctx, function_data: function_data, progs: &make_prog_list(),
    }
    tm
}

func (ssa_to_machine* m) lower_block(b* ssa_block) {
    i := 0
    for i < len(b.values) {
        value_id := b.values[i]
        m.lower_value(value_id)
        i = i + 1
    }
}

func (ssa_to_machine* m) lower_value(int value_id) {
}

func (ssa_to_machine* m) emit_alloca(int size) string {
    offset := m.ctx.alloc_state.next_stack_offset - size
    m.ctx.alloc_state.next_stack_offset = offset
    "-" + to_string(-offset) + "(%rbp)"
}

func (ssa_to_machine* m) emit_load(string addr, int reg) {
    reg_name := x86_64_reg_name(reg)
    instr := "\tmovq\t" + addr + ", %" + reg_name
    m.progs.append_prog(prog_op_load(), instr)
}

func (ssa_to_machine* m) emit_store(int reg, string addr) {
    reg_name := x86_64_reg_name(reg)
    instr := "\tmovq\t%" + reg_name + ", " + addr
    m.progs.append_prog(prog_op_store(), instr)
}

func (ssa_to_machine* m) emit_binary_op(string op, int left_reg, int right_reg, int result_reg) {
    left_name := x86_64_reg_name(left_reg)
    right_name := x86_64_reg_name(right_reg)
    result_name := x86_64_reg_name(result_reg)
    if left_reg != result_reg {
        instr := "\tmovq\t%" + left_name + ", %" + result_name
        m.progs.append_prog(prog_op_mov(), instr)
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
    m.progs.append_prog(1, instr)
}

func (ssa_to_machine* m) emit_comparison(string cond, int left_reg, int right_reg) int {
    left_name := x86_64_reg_name(left_reg)
    right_name := x86_64_reg_name(right_reg)
    cmp_instr := "\tcmpq\t%" + right_name + ", %" + left_name
    m.progs.append_prog(prog_op_cmp(), cmp_instr)
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
    m.progs.append_prog(20, set_instr)
    movz_instr := "\tmovzbl\t%al, %" + x86_64_reg_name(result_reg)
    m.progs.append_prog(prog_op_mov(), movz_instr)
    result_reg
}

func (ssa_to_machine* m) generate() prog_list {
    m.ctx.current_func = m.function_data.name
    m.ctx.emit_prologue()
    i := 0
    for i < m.function_data.block_count {
        m.lower_block(&m.function_data.blocks[i])
        i = i + 1
    }
    m.ctx.emit_epilogue()
    m.function_data.stack_size = m.ctx.alloc_state.get_stack_size()
    *m.progs
}
