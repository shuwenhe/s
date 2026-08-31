package backend

struct native_compiler {
    input_file: string
    output_file: string
    assembly_file: string
    object_file: string
    selector: instruction_selector
    builder: machine_code_builder
}

func new_native_compiler(input: string, output: string) native_compiler {
    compiler: native_compiler
    compiler.input_file = input
    compiler.output_file = output
    compiler.assembly_file = output + ".s"
    compiler.object_file = output + ".o"
    compiler.selector = new_instruction_selector()
    compiler.builder = new_machine_code_builder()
    compiler
}

func (nc* native_compiler) compile_to_assembly() int {
    nc.builder.emit_text_section()
    
    nc.builder.emit_global_symbol("main")
    nc.builder.emit_function_prologue("main")
    
    nc.builder.emit_mov_immediate_to_register(42, "rax")
    
    nc.builder.emit_function_epilogue()
    
    0
}

func (nc* native_compiler) assemble_to_object() int {
    0
}

func (nc* native_compiler) link_to_executable() int {
    0
}

func (nc* native_compiler) compile() int {
    result := nc.compile_to_assembly()
    if result != 0 {
        return result
    }
    
    result = nc.assemble_to_object()
    if result != 0 {
        return result
    }
    
    result = nc.link_to_executable()
    if result != 0 {
        return result
    }
    
    0
}

func (nc* native_compiler) get_assembly() string {
    nc.builder.get_assembly()
}
