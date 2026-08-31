package backend

struct register_info {
    name: string
    index: int
    is_available: bool
}

struct machine_code_builder {
    instructions: string[]
    labels: string[]
    functions: string[]
    next_reg: int
}

func new_machine_code_builder() machine_code_builder {
    builder: machine_code_builder
    builder.instructions = make(string[])
    builder.labels = make(string[])
    builder.functions = make(string[])
    builder.next_reg = 0
    builder
}

func (b* machine_code_builder) emit_text_section() {
    b.instructions = append(b.instructions, ".section\t.text")
}

func (b* machine_code_builder) emit_global_symbol(name: string) {
    b.instructions = append(b.instructions, ".globl\t" + name)
    b.instructions = append(b.instructions, ".type\t" + name + ", @function")
}

func (b* machine_code_builder) emit_function_prologue(name: string) {
    b.instructions = append(b.instructions, name + ":")
    b.instructions = append(b.instructions, "\tpush\t%rbp")
    b.instructions = append(b.instructions, "\tmov\t%rsp, %rbp")
}

func (b* machine_code_builder) emit_function_epilogue() {
    b.instructions = append(b.instructions, "\tpop\t%rbp")
    b.instructions = append(b.instructions, "\tret")
}

func (b* machine_code_builder) emit_mov_immediate_to_register(value: int, reg: string) {
    b.instructions = append(b.instructions, "\tmov\t$" + value as string + ", %" + reg)
}

func (b* machine_code_builder) emit_mov_register_to_register(src: string, dst: string) {
    b.instructions = append(b.instructions, "\tmov\t%" + src + ", %" + dst)
}

func (b* machine_code_builder) emit_add_registers(src: string, dst: string) {
    b.instructions = append(b.instructions, "\tadd\t%" + src + ", %" + dst)
}

func (b* machine_code_builder) emit_sub_registers(src: string, dst: string) {
    b.instructions = append(b.instructions, "\tsub\t%" + src + ", %" + dst)
}

func (b* machine_code_builder) emit_call(target: string) {
    b.instructions = append(b.instructions, "\tcall\t" + target)
}

func (b* machine_code_builder) emit_return_value(reg: string) {
    b.instructions = append(b.instructions, "\tmov\t%" + reg + ", %rax")
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
