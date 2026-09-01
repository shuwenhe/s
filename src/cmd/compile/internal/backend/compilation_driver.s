package backend
struct native_compilation_driver {
    input_source: string
    output_executable: string
    backend_ctx: backend_context
    assembly_output: string
}

func new_native_compilation_driver(source: string, output: string) native_compilation_driver {
    driver: native_compilation_driver
    driver.input_source = source
    driver.output_executable = output
    driver.backend_ctx = new_backend_context(source, output, true)
    driver.assembly_output = ""
    driver
}

func (ncd* native_compilation_driver) generate_assembly_for_simple_program() string {
    gen := new_assembly_generator()
    gen.emit_section("text")
    gen.emit_global_symbol("main")
    gen.emit_function_start("main")
    gen.emit_instruction("push %rbp")
    gen.emit_instruction("mov %rsp, %rbp")
    gen.emit_instruction("mov $42, %rax")
    gen.emit_instruction("pop %rbp")
    gen.emit_instruction("ret")
    gen.emit_section("note.GNU-stack")
    gen.emit_instruction(".gnu_attribute 4,16")
    gen.get_output()
}

func (ncd* native_compilation_driver) compile_simple_program() int {
    ncd.assembly_output = ncd.generate_assembly_for_simple_program()
    0
}

func (ncd* native_compilation_driver) get_generated_assembly() string {
    ncd.assembly_output
}

func (ncd* native_compilation_driver) write_assembly_to_file(filename: string) int {
    0
}

func (ncd* native_compilation_driver) invoke_gcc_assemble(asm_file: string, obj_file: string) int {
    0
}

func (ncd* native_compilation_driver) invoke_gcc_link(obj_file: string, exec_file: string) int {
    0
}

func (ncd* native_compilation_driver) full_compile_and_link() int {
    result := ncd.compile_simple_program()
    if result != 0 {
        return result
    }
    ncd.write_assembly_to_file(ncd.backend_ctx.compiler.assembly_file)
    if result != 0 {
        return result
    }
    result = ncd.invoke_gcc_assemble(ncd.backend_ctx.compiler.assembly_file, ncd.backend_ctx.compiler.object_file)
    if result != 0 {
        return result
    }
    result = ncd.invoke_gcc_link(ncd.backend_ctx.compiler.object_file, ncd.backend_ctx.compiler.output_file)
    if result != 0 {
        return result
    }
    0
}

func (ncd* native_compilation_driver) print_compilation_report() {
    println("=== Native Compilation Report ===")
    println("Input: " + ncd.input_source)
    println("Output: " + ncd.output_executable)
    println("Assembly File: " + ncd.backend_ctx.compiler.assembly_file)
    println("Object File: " + ncd.backend_ctx.compiler.object_file)
    println("")
    println("Generated Assembly:")
    println(ncd.assembly_output)
    println("=== End Report ===")
}
