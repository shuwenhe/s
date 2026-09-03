package backend
struct ir_instruction {
    opcode: string
    operand1: string
    operand2: string
    operand3: string
    result: string
}

struct instruction_selector {
    ir_instructions: ir_instruction[]
    builder: machine_code_builder
    allocator: register_allocator
}

func new_instruction_selector() instruction_selector {
    selector: instruction_selector
    selector.ir_instructions = make(ir_instruction[])
    selector.builder = new_machine_code_builder()
    selector.allocator = new_register_allocator()
    selector
}

func (instruction_selector is*) select_add_instruction( op1 string, op2 string, result string) {
    reg1 := is.allocator.allocate_for_variable(op1)
    reg2 := is.allocator.allocate_for_variable(op2)
    result_reg := is.allocator.allocate_for_variable(result)
    is.builder.emit_mov_register_to_register(reg1, result_reg)
    is.builder.emit_add_registers(reg2, result_reg)
}

func (instruction_selector is*) select_sub_instruction( op1 string, op2 string, result string) {
    reg1 := is.allocator.allocate_for_variable(op1)
    reg2 := is.allocator.allocate_for_variable(op2)
    result_reg := is.allocator.allocate_for_variable(result)
    is.builder.emit_mov_register_to_register(reg1, result_reg)
    is.builder.emit_sub_registers(reg2, result_reg)
}

func (instruction_selector is*) select_mov_instruction( src string, dst string) {
    src_reg := is.allocator.allocate_for_variable(src)
    dst_reg := is.allocator.allocate_for_variable(dst)
    is.builder.emit_mov_register_to_register(src_reg, dst_reg)
}

func (instruction_selector is*) select_call_instruction( target string, args []string) {
    param_regs := make([]string)
    param_regs = append(param_regs, "rdi")
    param_regs = append(param_regs, "rsi")
    param_regs = append(param_regs, "rdx")
    param_regs = append(param_regs, "rcx")
    param_regs = append(param_regs, "r8")
    param_regs = append(param_regs, "r9")
    i := 0
    for i < len(args) && i < len(param_regs) {
        arg_reg := is.allocator.allocate_for_variable(args[i])
        is.builder.emit_mov_register_to_register(arg_reg, param_regs[i])
        i = i + 1
    }
    is.builder.emit_call(target)
}

func (instruction_selector is*) select_return_instruction( value string) {
    val_reg := is.allocator.allocate_for_variable(value)
    is.builder.emit_return_value(val_reg)
}

func (instruction_selector is*) get_assembly() string {
    is.builder.get_assembly()
}
