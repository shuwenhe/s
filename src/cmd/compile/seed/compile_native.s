package seed
use seed.codegen.codegen
use seed.codegen.register
use seed.codegen.stackframe
use seed.codegen.instruction_select
use seed.codegen.linker
use std.vec.vec
use std.string.string
use std.file.file
struct compiler_native {
    source_file: string
    output_file: string
    asm_file: string
    obj_file: string
    codegen: codegen_context
    toolchain: compiler_toolchain
}

func compiler_native_create(source_file: string, output_file: string) compiler_native {
    compiler: compiler_native
    compiler.source_file = source_file
    compiler.output_file = output_file
    compiler.asm_file = output_file + ".s"
    compiler.obj_file = output_file + ".o"
    compiler.codegen = codegen_context_create("program")
    compiler.toolchain = toolchain_create()
    compiler
}

func (compiler* compiler_native) generate_assembly(program: &runtime_program) (int, string) {
    codegen_emit_preamble(&compiler.codegen)
    for i < program.function_count {
        fn := program.functions[i]
        compiler.generate_function(fn)
    }
    0, ""
}

func (compiler* compiler_native) generate_function(fn: &runtime_function) {
    codegen_emit_function_prologue(&compiler.codegen, fn.name, fn.param_count)
    allocator := register_allocator_create()
    frame := stack_frame_create(fn.param_count)
    for pc in fn.start_pc..fn.end_pc {
        ins := &compiler.codegen.prog.data[pc]
        compiler.generate_instruction(&allocator, &frame, ins)
    }
    codegen_emit_function_epilogue(&compiler.codegen)
}

func (compiler* compiler_native) generate_instruction(ra: &mut register_allocator, sf: &mut stack_frame, ins: &runtime_ins) {
    if ins.op == "MOV" {
        instruction_select_mov(&compiler.codegen, ra, ins.op1, ins.result)
    } else if ins.op == "ADD" {
        instruction_select_add(&compiler.codegen, ra, ins.op1, ins.op2, ins.result)
    } else if ins.op == "SUB" {
        instruction_select_sub(&compiler.codegen, ra, ins.op1, ins.op2, ins.result)
    } else if ins.op == "MUL" {
        instruction_select_mul(&compiler.codegen, ra, ins.op1, ins.op2, ins.result)
    } else if ins.op == "CMP" {
        instruction_select_cmp(&compiler.codegen, ra, ins.op1, ins.op2)
    } else if ins.op == "CALL" {
        compiler.codegen.emit_line("    call " + ins.result)
    } else if ins.op == "RET" {
        instruction_select_ret(&compiler.codegen, ra, ins.op1)
    } else if ins.op == "JUMP" {
        compiler.codegen.emit_line("    jmp " + ins.result)
    } else if ins.op == "JUMP_IF_FALSE" {
        compiler.codegen.emit_line("    jne " + ins.result)
    }
}

func (compiler* compiler_native) write_assembly_file() (int, string) {
    codegen_write_to_file(&compiler.codegen, compiler.asm_file)
}

func (compiler* compiler_native) compile_to_executable() (int, string) {
    exit_code, msg := compiler.write_assembly_file()
    if exit_code != 0 {
        return exit_code, "Failed to write assembly: " + msg
    }
    exit_code, msg = compiler.toolchain.assemble(compiler.asm_file, compiler.obj_file)
    if exit_code != 0 {
        return exit_code, "Assembly failed: " + msg
    }
    obj_files := vec[]()
    obj_files.push(compiler.obj_file)
    exit_code, msg = compiler.toolchain.link_executable(&obj_files, compiler.output_file)
    if exit_code != 0 {
        return exit_code, "Linking failed: " + msg
    }
    0, ""
}

func compiler_compile_native(source: string, output: string) (int, string) {
    compiler := compiler_native_create(source, output)
    compiler.compile_to_executable()
}
