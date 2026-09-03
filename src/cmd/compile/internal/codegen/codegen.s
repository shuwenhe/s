package compile.internal.codegen
use compile.internal.link
use compile.internal.obj
extern "intrinsic" func __host_write_text_file(string path, string contents) int;
extern "intrinsic" func __host_make_executable(string path) int;
struct codegen_config {
    string target_arch
    int64 code_section_align
    int64 data_section_align
    bool emit_debug_info
    bool optimize_size
}

func make_codegen_config(string arch) codegen_config {
    codegen_config {
        target_arch: arch, code_section_align 16 as int64, data_section_align 8 as int64, emit_debug_info false, optimize_size false,
    }
}

struct codegen_context {
    machine_code_gen* gen
    symbol_table* symtab
    codegen_config config
    int64 code_offset
    int64 data_offset
    []string generated_functions
}

func make_codegen_context(machine_code_gen* mcg, symbol_table* st, codegen_config cfg) codegen_context {
    codegen_context {
        gen: mcg, symtab st, config cfg, code_offset 0 as int64, data_offset 0 as int64, generated_functions []string(),
    }
}

func (ctx* codegen_context) codegen_func_main() string {
    func_name := "main"
    idx := ctx.symtab.add_symbol(func_name, symbol_bind_global, symbol_type_func, ctx.code_offset, 0 as int64, 1)
    err := ctx.gen.emit_simple_func(func_name)
    if err != "" {
        return "Failed to emit main: " + err
    }
    ctx.generated_functions = append(ctx.generated_functions, func_name)
    ""
}

func (ctx* codegen_context) codegen_func_add() string {
    func_name := "add"
    idx := ctx.symtab.add_symbol(func_name, symbol_bind_global, symbol_type_func, ctx.code_offset, 0 as int64, 1)
    err := ctx.gen.emit_add_function()
    if err != "" {
        return "Failed to emit add: " + err
    }
    ctx.generated_functions = append(ctx.generated_functions, func_name)
    ""
}

func (ctx* codegen_context) generate_object_file(string output_path) string {
    builder := make_object_file_builder(ctx.symtab, &ctx.gen.reloc_ctx)
    builder.set_code(ctx.gen.get_code())
    image := builder.build_elf64(elf_machine_x86_64)
    err := builder.write_to_file(output_path, image)
    if err != "" { return err }
    ""
}

struct object_file_builder {
    elf_writer* writer
    symbol_table* symtab
    relocation_context* reloc_ctx
    []int8 code
    []int8 data
}

func make_object_file_builder(symbol_table* st, relocation_context* rc) object_file_builder {
    object_file_builder {
        writer: nil as elf_writer*, symtab st, reloc_ctx rc,
        code: []int8()(),
        data: []int8()(),
    }
}

func (builder* object_file_builder) set_code([]int8 code) {
    builder.code = code
}

func (builder* object_file_builder) set_data([]int8 data) {
    builder.data = data
}

func (builder* object_file_builder) build_elf64(elf_machine machine) []int8 {
    writer := make_elf_writer(machine)
    code_offset := 120 as int64
    image_base := 0x400000 as int64
    entry := image_base + code_offset
    file_size := code_offset + (len(builder.code) as int64)
    writer.write_elf_header(machine)
    writer.write_u64(1 as int64)
    writer.write_u64(5 as int64)
    writer.write_u64(0 as int64)
    writer.write_u64(image_base)
    writer.write_u64(image_base)
    writer.write_u64(file_size)
    writer.write_u64(file_size)
    writer.write_u64(0x1000 as int64)
    data := writer.get_data()
    data[24] = (entry & 255) as int8
    data[25] = ((entry >> 8) & 255) as int8
    data[26] = ((entry >> 16) & 255) as int8
    data[27] = ((entry >> 24) & 255) as int8
    data[28] = ((entry >> 32) & 255) as int8
    data[29] = ((entry >> 40) & 255) as int8
    data[30] = ((entry >> 48) & 255) as int8
    data[31] = ((entry >> 56) & 255) as int8
    i := 0
    for i < len(builder.code) {
        data = append(data, builder.code[i])
        i = i + 1
    }
    data
}

func (builder* object_file_builder) write_to_file(string path, []int8 data) string {
    contents := ""
    i := 0
    for i < len(data) {
        contents = contents + __host_byte_string((data[i] as int) & 255)
        i = i + 1
    }
    if __host_write_text_file(path, contents) != 0 { return "cannot write ELF output" }
    if __host_make_executable(path) != 0 { return "cannot mark ELF output executable" }
    ""
}

struct codegen_pipeline {
    codegen_context ctx
}

func make_codegen_pipeline(machine_code_gen* gen, symbol_table* st, codegen_config cfg) codegen_pipeline {
    codegen_pipeline {
        ctx: make_codegen_context(gen, st, cfg),
    }
}

func (pipeline* codegen_pipeline) generate_all() ([]int8, string) {
    err := pipeline.ctx.codegen_func_main()
    if err != "" {
        return nil, "Failed to generate main: " + err
    }
    err = pipeline.ctx.codegen_func_add()
    if err != "" {
        return nil, "Failed to generate add: " + err
    }
    code := pipeline.ctx.gen.get_code()
    return code, ""
}

func (pipeline* codegen_pipeline) get_symbol_table() symbol_table* {
    pipeline.ctx.symtab
}

func (pipeline* codegen_pipeline) dump_stats() string {
    result := "Codegen Statistics:\n"
    result = result + "  Generated Functions: " + (len(pipeline.ctx.generated_functions) as string) + "\n"
    result = result + "  Code Offset: " + (pipeline.ctx.code_offset as string) + "\n"
    result = result + "  Data Offset: " + (pipeline.ctx.data_offset as string) + "\n"
    result
}
