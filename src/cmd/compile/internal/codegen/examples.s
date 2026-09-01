package compile.internal.codegen

use compile.internal.link
use compile.internal.obj

struct compilation_session {
    link_context* link_ctx
    machine_code_gen* mcg
    symbol_table* symtab
    relocation_context reloc_ctx
    codegen_pipeline* pipeline
}

func make_compilation_session() compilation_session {
    link_ctx := &(link_make_link_context())
    
    mcg := &(make_machine_code_gen(link_ctx))
    
    symtab := &(make_symbol_table())
    
    cfg := make_codegen_config("amd64")
    
    pipeline := &(make_codegen_pipeline(mcg, symtab, cfg))
    
    compilation_session {
        link_ctx: link_ctx,
        mcg: mcg,
        symtab: symtab,
        reloc_ctx: make_relocation_context(),
        pipeline: pipeline,
    }
}

func (session* compilation_session) compile_program() string {
    code, err := session.pipeline.generate_all()
    if err != "" {
        return "Compilation error: " + err
    }
    
    ""
}

func (session* compilation_session) generate_object_file(string output_path) string {
    err := session.pipeline.ctx.generate_object_file(output_path)
    if err != "" { return err }
    "direct machine-code ELF written to " + output_path
}

func (session* compilation_session) dump_compilation_info() string {
    result := "\n=== S Compiler Direct Machine Code Generation ===\n"
    result = result + "\n" + session.pipeline.dump_stats()
    result = result + "\n" + session.mcg.dump_assembly()
    result = result + "\n" + session.symtab.dump()
    result = result + "\n" + session.reloc_ctx.dump()
    result
}

func compile_simple_program() string {
    session := make_compilation_session()
    
    err := session.compile_program()
    if err != "" {
        return "Compilation failed: " + err
    }
    
    session.dump_compilation_info()
}

func compile_with_output(string output_file) (string, string) {
    session := make_compilation_session()
    
    err := session.compile_program()
    if err != "" {
        return "", "Compilation failed: " + err
    }
    
    obj_info := session.generate_object_file(output_file)
    
    info := session.dump_compilation_info()
    
    return info, obj_info
}

func demonstrate_instruction_encoding() string {
    result := "=== Instruction Encoding Demonstration ===\n\n"
    
    result = result + "MOV reg to reg encoding:\n"
    mov_code := encode_mov_reg_to_reg(0, 1)
    i := 0
    for i < len(mov_code) {
        result = result + byte_to_hex(mov_code[i]) + " "
        i = i + 1
    }
    result = result + "\n\n"
    
    result = result + "MOV immediate to register encoding:\n"
    mov_imm_code := encode_mov_imm_to_reg(42 as int64, 0)
    i = 0
    for i < len(mov_imm_code) {
        result = result + byte_to_hex(mov_imm_code[i]) + " "
        i = i + 1
    }
    result = result + "\n\n"
    
    result = result + "ADD register encoding:\n"
    add_code := encode_add_reg_to_reg(0, 1)
    i = 0
    for i < len(add_code) {
        result = result + byte_to_hex(add_code[i]) + " "
        i = i + 1
    }
    result = result + "\n\n"
    
    result = result + "PUSH/POP/RET encoding:\n"
    push_code := encode_push_reg(0)
    pop_code := encode_pop_reg(0)
    ret_code := encode_ret()
    
    i = 0
    for i < len(push_code) {
        result = result + byte_to_hex(push_code[i]) + " "
        i = i + 1
    }
    result = result + " "
    
    i = 0
    for i < len(pop_code) {
        result = result + byte_to_hex(pop_code[i]) + " "
        i = i + 1
    }
    result = result + " "
    
    i = 0
    for i < len(ret_code) {
        result = result + byte_to_hex(ret_code[i]) + " "
        i = i + 1
    }
    result = result + "\n\n"
    
    result
}

func demonstrate_linking() string {
    result := "=== Linking Demonstration ===\n\n"
    
    ctx := make_link_context()
    
    main_sym, _ := ctx.create_symbol("main", compile.internal.link.sym_type_text)
    add_sym, _ := ctx.create_symbol("add", compile.internal.link.sym_type_text)
    
    main_sym.size = 32 as int64
    main_sym.is_defined = true
    
    add_sym.size = 24 as int64
    add_sym.is_defined = true
    
    result = result + "Symbols:\n"
    i := 0
    for i < len(ctx.symbols) {
        sym := ctx.symbols[i]
        result = result + "  " + sym.name + ": size=" + (sym.size as string) + ", defined=" + (sym.is_defined as string) + "\n"
        i = i + 1
    }
    
    result = result + "\nText Section Size: " + (ctx.text_size as string) + " bytes\n"
    result = result + "Data Section Size: " + (ctx.data_size as string) + " bytes\n"
    
    result
}

func demonstrate_elf_generation() string {
    result := "=== ELF64 Generation Demonstration ===\n\n"
    
    writer := make_elf_writer(elf_machine_x86_64)
    
    writer.write_elf_header(elf_machine_x86_64)
    
    result = result + "ELF Header written:\n"
    result = result + "  Machine: x86-64\n"
    result = result + "  Type: Object File\n"
    result = result + "  Entry Point: 0x0\n"
    
    data := writer.get_data()
    result = result + "  Header Size: " + (len(data) as string) + " bytes\n\n"
    
    result = result + "Raw ELF Header Bytes:\n"
    i := 0
    for i < len(data) {
        result = result + byte_to_hex(data[i]) + " "
        if ((i + 1) % 16 == 0) {
            result = result + "\n"
        }
        i = i + 1
    }
    result = result + "\n"
    
    result
}

func run_all_demonstrations() string {
    result := "\n========================================\n"
    result = result + "S LANGUAGE COMPILER - DIRECT MACHINE CODE GENERATION\n"
    result = result + "Referencing Go Compiler Architecture\n"
    result = result + "========================================\n"
    
    result = result + demonstrate_instruction_encoding()
    result = result + demonstrate_linking()
    result = result + demonstrate_elf_generation()
    result = result + compile_simple_program()
    
    result
}
