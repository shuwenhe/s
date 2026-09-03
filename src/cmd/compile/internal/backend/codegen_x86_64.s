package backend
struct register_info {
    name: string
    index: int
    is_available: bool
}

struct machine_code_builder {
    instructions: []string
    machine_code: []int
    labels: []string
    functions: []string
    next_reg: int
}

func new_machine_code_builder() machine_code_builder {
    builder: machine_code_builder
    builder.instructions = make([]string)
    builder.machine_code = make([]int)
    builder.labels = make([]string)
    builder.functions = make([]string)
    builder.next_reg = 0
    builder
}

func (b* machine_code_builder) emit_byte(int value) {
    b.machine_code = append(b.machine_code, value & 255)
}

func (b* machine_code_builder) emit_u32(int value) {
    b.emit_byte(value & 255)
    b.emit_byte((value >> 8) & 255)
    b.emit_byte((value >> 16) & 255)
    b.emit_byte((value >> 24) & 255)
}

func (b* machine_code_builder) emit_u64(int value) {
    b.emit_u32(value & 4294967295)
    b.emit_u32((value >> 32) & 4294967295)
}

func (b* machine_code_builder) reg_code(string reg) int {
    switch reg {
        case "rax" : 0,
        case "rcx" : 1,
        case "rdx" : 2,
        case "rbx" : 3,
        case "rsp" : 4,
        case "rbp" : 5,
        case "rsi" : 6,
        case "rdi" : 7,
        case "r8" : 8,
        case "r9" : 9,
        case "r10" : 10,
        case "r11" : 11,
        case "r12" : 12,
        case "r13" : 13,
        case "r14" : 14,
        case "r15" : 15,
        default : -1
    }
}

func (b* machine_code_builder) emit_rex(bool w, int r, int bbit) {
    prefix := 64
    if w {
        prefix = prefix + 8
    }
    if r >= 8 {
        prefix = prefix + 4
    }
    if bbit >= 8 {
        prefix = prefix + 1
    }
    if prefix != 64 {
        b.emit_byte(prefix)
    }
}

func (b* machine_code_builder) emit_text_section() {
    b.instructions = append(b.instructions, ".section\t.text")
}

func (b* machine_code_builder) emit_global_symbol( name string) {
    b.instructions = append(b.instructions, ".globl\t" + name)
    b.instructions = append(b.instructions, ".type\t" + name + ", @function")
}

func (b* machine_code_builder) emit_function_prologue( name string) {
    b.instructions = append(b.instructions, name + ":")
    b.instructions = append(b.instructions, "\tpush\t%rbp")
    b.instructions = append(b.instructions, "\tmov\t%rsp, %rbp")
    b.emit_byte(85)
    b.emit_rex(true, 4, 5)
    b.emit_byte(137)
    b.emit_byte(229)
}

func (b* machine_code_builder) emit_function_epilogue() {
    b.instructions = append(b.instructions, "\tpop\t%rbp")
    b.instructions = append(b.instructions, "\tret")
    b.emit_byte(93)
    b.emit_byte(195)
}

func (b* machine_code_builder) emit_mov_immediate_to_register( value int, reg string) {
    b.instructions = append(b.instructions, "\tmov\t$" + value as string + ", %" + reg)
    reg_id := b.reg_code(reg)
    if reg_id >= 0 {
        b.emit_rex(true, 0, reg_id)
        b.emit_byte(184 + (reg_id & 7))
        b.emit_u64(value)
    }
}

func (b* machine_code_builder) emit_mov_register_to_register( src string, dst string) {
    b.instructions = append(b.instructions, "\tmov\t%" + src + ", %" + dst)
    src_id := b.reg_code(src)
    dst_id := b.reg_code(dst)
    if src_id >= 0 && dst_id >= 0 {
        b.emit_rex(true, src_id, dst_id)
        b.emit_byte(137)
        b.emit_byte(192 + ((src_id & 7) << 3) + (dst_id & 7))
    }
}

func (b* machine_code_builder) emit_add_registers( src string, dst string) {
    b.instructions = append(b.instructions, "\tadd\t%" + src + ", %" + dst)
    src_id := b.reg_code(src)
    dst_id := b.reg_code(dst)
    if src_id >= 0 && dst_id >= 0 {
        b.emit_rex(true, src_id, dst_id)
        b.emit_byte(1)
        b.emit_byte(192 + ((src_id & 7) << 3) + (dst_id & 7))
    }
}

func (b* machine_code_builder) emit_sub_registers( src string, dst string) {
    b.instructions = append(b.instructions, "\tsub\t%" + src + ", %" + dst)
    src_id := b.reg_code(src)
    dst_id := b.reg_code(dst)
    if src_id >= 0 && dst_id >= 0 {
        b.emit_rex(true, src_id, dst_id)
        b.emit_byte(41)
        b.emit_byte(192 + ((src_id & 7) << 3) + (dst_id & 7))
    }
}

func (b* machine_code_builder) emit_call( target string) {
    b.instructions = append(b.instructions, "\tcall\t" + target)
}

func (b* machine_code_builder) emit_return_value( reg string) {
    b.instructions = append(b.instructions, "\tmov\t%" + reg + ", %rax")
    b.emit_mov_register_to_register(reg, "rax")
}

func (b* machine_code_builder) get_assembly() string {
    result := ""
    i := 0
    for i < len(b.instructions) {
        result = result + b.instructions[i] + "\n"
        i = i + 1
    }
    result
}

func (b* machine_code_builder) get_machine_code() []int {
    b.machine_code
}
