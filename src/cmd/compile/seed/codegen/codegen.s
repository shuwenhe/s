package seed.codegen
use std.vec.vec
use std.string.string
use std.file.file
struct codegen_context {
    program_name: string
    functions: code_function[]
    globals: code_global[]
    assembly_lines: []string
    next_label_id: int
}

struct code_function {
    name: string
    params: []string
    locals: code_local[]
    instructions: code_instruction[]
    prologue: []string
    epilogue: []string
}

struct code_local {
    name: string
    offset: int
    size: int
}

struct code_instruction {
    op: string
    operand1: string
    operand2: string
    operand3: string
    result: string
}

struct code_global {
    name: string
    value: string
}

func codegen_context_create(string prog_name) codegen_context {
    ctx: codegen_context
    ctx.program_name = prog_name
    ctx.functions = vec[]()
    ctx.globals = vec[]()
    ctx.assembly_lines = vec[]()
    ctx.next_label_id = 0
    ctx
}

func (ctx* codegen_context) gen_label() string {
    label_id := ctx.next_label_id
    ctx.next_label_id = ctx.next_label_id + 1
    ".L" + label_id as string
}

func (ctx* codegen_context) emit_line( line string) {
    ctx.assembly_lines.push(line)
}

func (ctx* codegen_context) emit_comment( text string) {
    ctx.emit_line("# " + text)
}

func (ctx* codegen_context) emit_label( label string) {
    ctx.emit_line(label + ":")
}

func (ctx* codegen_context) emit_directive( directive string) {
    ctx.emit_line("." + directive)
}

func codegen_emit_preamble(ctx* codegen_context) {
    ctx.emit_comment("Generated assembly for " + ctx.program_name)
    ctx.emit_directive("text")
    ctx.emit_directive("globl main")
    ctx.emit_line("")
}

func codegen_emit_function_prologue(ctx* codegen_context, string fn_name, int param_count) {
    ctx.emit_label(fn_name)
    ctx.emit_line("    push %rbp")
    ctx.emit_line("    mov %rsp, %rbp")
    if param_count > 0 {
        stack_space := (param_count + 1) * 8
        ctx.emit_line("    sub $" + stack_space as string + ", %rsp")
    }
}

func codegen_emit_function_epilogue(ctx* codegen_context) {
    ctx.emit_line("    leave")
    ctx.emit_line("    ret")
}

func codegen_emit_mov_reg_imm(ctx* codegen_context, string reg, int imm) {
    ctx.emit_line("    mov $" + imm as string + ", %" + reg)
}

func codegen_emit_mov_reg_reg(ctx* codegen_context, string dst, string src) {
    ctx.emit_line("    mov %" + src + ", %" + dst)
}

func codegen_emit_add_reg_reg(ctx* codegen_context, string dst, string src) {
    ctx.emit_line("    add %" + src + ", %" + dst)
}

func codegen_emit_sub_reg_reg(ctx* codegen_context, string dst, string src) {
    ctx.emit_line("    sub %" + src + ", %" + dst)
}

func codegen_emit_mul_reg_reg(ctx* codegen_context, string dst, string src) {
    ctx.emit_line("    imul %" + src + ", %" + dst)
}

func codegen_emit_cmp_reg_reg(ctx* codegen_context, string dst, string src) {
    ctx.emit_line("    cmp %" + src + ", %" + dst)
}

func codegen_emit_jmp(ctx* codegen_context, string label) {
    ctx.emit_line("    jmp " + label)
}

func codegen_emit_jne(ctx* codegen_context, string label) {
    ctx.emit_line("    jne " + label)
}

func codegen_emit_je(ctx* codegen_context, string label) {
    ctx.emit_line("    je " + label)
}

func codegen_emit_call(ctx* codegen_context, string fn_name) {
    ctx.emit_line("    call " + fn_name)
}

func codegen_emit_ret_reg(ctx* codegen_context, string reg) {
    ctx.emit_line("    mov %" + reg + ", %rax")
    ctx.emit_line("    leave")
    ctx.emit_line("    ret")
}

func codegen_get_assembly(ctx* codegen_context) []string {
    ctx.assembly_lines
}

func codegen_write_to_file(ctx* codegen_context, string output_file) (int, string) {
    f := file_create(output_file)
    if f.is_error {
        return -1, "Failed to create file: " + output_file
    }
    for i < ctx.assembly_lines.len() {
        line := ctx.assembly_lines[i]
        f.write_line(line)
    }
    f.close()
    0, ""
}
