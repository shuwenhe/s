package backend
struct codegen_context {
    prog_list* progs
    reg_alloc_state* alloc_state
    string current_func
    int current_pos
    int next_label_id
    []string labels
}

func make_codegen_context() codegen_context {
    pl := make_prog_list()
    ctx: codegen_context
    ctx.progs = &pl
    ctx.alloc_state = &make_reg_alloc_state()
    ctx.current_func = ""
    ctx.current_pos = 0
    ctx.next_label_id = 0
    ctx.labels = []string()
    ctx
}

func x86_64_reg_name(int reg_id) string {
    switch reg_id {
        case 0 : "rax",
        case 1 : "rbx",
        case 2 : "rcx",
        case 3 : "rdx",
        case 4 : "rsi",
        case 5 : "rdi",
        case 6 : "r8",
        case 7 : "r9",
        case 8 : "r10",
        case 9 : "r11",
        case 10 : "r12",
        case 11 : "r13",
        case 12 : "r14",
        case 13 : "r15",
        case 14 : "rbp",
        default : "unknown"
    }
}

func x86_64_reg_id(string name) int {
    switch name {
        case "rax" : 0,
        case "rbx" : 1,
        case "rcx" : 2,
        case "rdx" : 3,
        case "rsi" : 4,
        case "rdi" : 5,
        case "r8" : 6,
        case "r9" : 7,
        case "r10" : 8,
        case "r11" : 9,
        case "r12" : 10,
        case "r13" : 11,
        case "r14" : 12,
        case "r15" : 13,
        case "rbp" : 14,
        default : -1
    }
}

func (ctx* codegen_context) new_label() string {
    label := "L" + to_string(ctx.next_label_id)
    ctx.next_label_id = ctx.next_label_id + 1
    ctx.labels = append(ctx.labels, label)
    label
}

func (ctx* codegen_context) emit_mov(string src, string dst) {
    instr := "\tmov\t" + src + ", " + dst
    ctx.progs.append_prog(prog_op_mov(), instr)
    ctx.current_pos = ctx.current_pos + 1
}

func (ctx* codegen_context) emit_add(string src, string dst) {
    instr := "\tadd\t" + src + ", " + dst
    ctx.progs.append_prog(prog_op_add(), instr)
    ctx.current_pos = ctx.current_pos + 1
}

func (ctx* codegen_context) emit_sub(string src, string dst) {
    instr := "\tsub\t" + src + ", " + dst
    ctx.progs.append_prog(prog_op_sub(), instr)
    ctx.current_pos = ctx.current_pos + 1
}

func (ctx* codegen_context) emit_mul(string src, string dst) {
    instr := "\timul\t" + src + ", " + dst
    ctx.progs.append_prog(prog_op_mul(), instr)
    ctx.current_pos = ctx.current_pos + 1
}

func (ctx* codegen_context) emit_div(string divisor) {
    instr := "\tidiv\t" + divisor
    ctx.progs.append_prog(prog_op_div(), instr)
    ctx.current_pos = ctx.current_pos + 1
}

func (ctx* codegen_context) emit_cmp(string src, string dst) {
    instr := "\tcmp\t" + src + ", " + dst
    ctx.progs.append_prog(prog_op_cmp(), instr)
    ctx.current_pos = ctx.current_pos + 1
}

func (ctx* codegen_context) emit_jmp(string label) {
    instr := "\tjmp\t" + label
    ctx.progs.append_prog(prog_op_jmp(), instr)
    ctx.current_pos = ctx.current_pos + 1
}

func (ctx* codegen_context) emit_je(string label) {
    instr := "\tje\t" + label
    ctx.progs.append_prog(prog_op_je(), instr)
    ctx.current_pos = ctx.current_pos + 1
}

func (ctx* codegen_context) emit_jne(string label) {
    instr := "\tjne\t" + label
    ctx.progs.append_prog(prog_op_jne(), instr)
    ctx.current_pos = ctx.current_pos + 1
}

func (ctx* codegen_context) emit_call(string func_name) {
    instr := "\tcall\t" + func_name
    ctx.progs.append_prog(prog_op_call(), instr)
    ctx.current_pos = ctx.current_pos + 1
}

func (ctx* codegen_context) emit_ret() {
    instr := "\tret"
    ctx.progs.append_prog(prog_op_ret(), instr)
    ctx.current_pos = ctx.current_pos + 1
}

func (ctx* codegen_context) emit_push(string reg) {
    instr := "\tpush\t" + reg
    ctx.progs.append_prog(prog_op_push(), instr)
    ctx.current_pos = ctx.current_pos + 1
}

func (ctx* codegen_context) emit_pop(string reg) {
    instr := "\tpop\t" + reg
    ctx.progs.append_prog(prog_op_pop(), instr)
    ctx.current_pos = ctx.current_pos + 1
}

func (ctx* codegen_context) emit_lea(string src, string dst) {
    instr := "\tlea\t" + src + ", " + dst
    ctx.progs.append_prog(prog_op_lea(), instr)
    ctx.current_pos = ctx.current_pos + 1
}

func (ctx* codegen_context) emit_label(string label) {
    ctx.progs.append_prog(20, label + ":")
}

func (ctx* codegen_context) emit_prologue() {
    ctx.emit_push("%rbp")
    ctx.emit_mov("%rsp", "%rbp")
}

func (ctx* codegen_context) emit_epilogue() {
    ctx.emit_pop("%rbp")
    ctx.emit_ret()
}
