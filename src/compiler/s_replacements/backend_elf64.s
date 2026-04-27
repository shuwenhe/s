fn build_executable(source, output_path) {
    if is_compiler_runtime_entry(source) {
        let base_compiler = get_env("s_bootstrap_base_compiler", "/app/s/bin/s-native")
        if output_path == base_compiler {
            panic("refusing to generate a launcher that execs itself; set s_bootstrap_base_compiler to a different binary")
        }
        let asm = emit_runtime_launcher_asm(base_compiler)
        write_file(output_path + ".s", asm)
        os.exec(["as", "-o", output_path + ".o", output_path + ".s"])
        os.exec(["ld", "-o", output_path, output_path + ".o"])
        return
    }
    let program = compile_program(source)
    let asm = emit_asm(program)
    write_file(output_path + ".s", asm)
    os.exec(["as", "-o", output_path + ".o", output_path + ".s"])
    os.exec(["ld", "-o", output_path, output_path + ".o"])
}

fn is_compiler_runtime_entry(source) -> bool {
    return false
}

fn emit_runtime_launcher_asm(base_compiler_path: string): string {
    let arch = os.arch()
    if arch == "aarch64" {
        return ".section .rodata\nbase_compiler_path:\n    .asciz '" + base_compiler_path + "'\n\n.section .text\n.global _start\n_start:\n    ldr x9, [sp]\n    add x1, sp, #8\n    add x2, x1, x9, lsl #3\n    add x2, x2, #8\n    adrp x0, base_compiler_path\n    add x0, x0, :lo12:base_compiler_path\n    mov x8, #221\n    svc #0\n\n    mov x0, #127\n    mov x8, #93\n    svc #0\n"
    }
    if arch == "x86_64" {
        return ".section .rodata\nbase_compiler_path:\n    .asciz '" + base_compiler_path + "'\n\n.section .text\n.global _start\n_start:\n    mov (%rsp), %rcx\n    lea 8(%rsp), %r8\n    lea 16(%rsp,%rcx,8), %rdx\n    lea base_compiler_path(%rip), %rdi\n    mov %r8, %rsi\n    mov $59, %rax\n    syscall\n\n    mov $60, %rax\n    mov $127, %rdi\n    syscall\n"
    }
    panic("unsupported architecture for runtime launcher")
}

fn emit_asm(program): string {
    return ""
}
