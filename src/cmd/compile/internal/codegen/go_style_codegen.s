package compile.internal.codegen
use compile.internal.link
use compile.internal.obj
struct go_style_code_generator {
    machine_code_gen* mcg
    symbol_table* symtab
    relocation_context* reloc_ctx
    codegen_config config
    int current_func_id
    int64 current_section_offset
}

func make_go_style_code_generator(
    machine_code_gen* mcg,
    symbol_table* symtab,
    relocation_context* reloc_ctx,
    codegen_config cfg
) go_style_code_generator {
    go_style_code_generator {
        mcg: mcg, symtab symtab, reloc_ctx reloc_ctx, config cfg, current_func_id 0, current_section_offset 0 as int64,
    }
}

func (gen* go_style_code_generator) gen_func_body(string func_name, int64 stack_size) string {
    prologue := encode_push_reg(5)
    prologue = append_bytes(prologue, encode_mov_reg_to_reg(5, 4))
    if stack_size > 0 {
        sub_code := encode_sub_imm_from_reg(4 as int, stack_size)
        prologue = append_bytes(prologue, sub_code)
    }
    gen.mcg.stream.emit_raw_bytes(prologue)
    ""
}

func (gen* go_style_code_generator) gen_func_epilogue(int64 stack_size) string {
    epilogue := int8[]()()
    if stack_size > 0 {
        add_code := encode_add_imm_to_reg(4 as int, stack_size)
        epilogue = append_bytes(epilogue, add_code)
    }
    epilogue = append_bytes(epilogue, encode_pop_reg(5))
    epilogue = append_bytes(epilogue, encode_ret())
    gen.mcg.stream.emit_raw_bytes(epilogue)
    ""
}

func (gen* go_style_code_generator) gen_call(string func_name, int arg_count) string {
    call_code := encode_call_direct(func_name)
    gen.mcg.stream.emit_raw_bytes(call_code)
    gen.reloc_ctx.add_relocation(
        gen.current_section_offset + (len(call_code) as int64) - 4 as int64,
        reloc_type_pc32,
        func_name,
        -(4 as int64),
        4 as int32
    )
    gen.current_section_offset = gen.current_section_offset + (len(call_code) as int64)
    ""
}

func (gen* go_style_code_generator) gen_load_const(int64 value, int dest_reg) string {
    code := encode_mov_imm_to_reg(value, dest_reg)
    gen.mcg.stream.emit_raw_bytes(code)
    gen.current_section_offset = gen.current_section_offset + (len(code) as int64)
    ""
}

func (gen* go_style_code_generator) gen_binop(string op, int left_reg, int right_reg, int result_reg) string {
    code := int8[]()()
    if op == "add" {
        code = encode_add_reg_to_reg(left_reg, right_reg)
    } else if op == "sub" {
        code = encode_sub_reg_from_reg(left_reg, right_reg)
    } else if op == "mul" {
        code = encode_imul_reg_reg(left_reg, right_reg)
    } else if op == "cmp" {
        code = encode_cmp_reg_reg(left_reg, right_reg)
    }
    if result_reg != left_reg {
        mov_code := encode_mov_reg_to_reg(result_reg, left_reg)
        code = append_bytes(code, mov_code)
    }
    gen.mcg.stream.emit_raw_bytes(code)
    gen.current_section_offset = gen.current_section_offset + (len(code) as int64)
    ""
}

func (gen* go_style_code_generator) gen_store(int source_reg, int64 stack_offset, int size) string {
    code := int8[]()()
    if size == 8 {
        code = encode_store_reg_to_memory(source_reg, 5 as int, stack_offset)
    } else if size == 4 {
        code = encode_store_reg_to_memory_32(source_reg, 5 as int, stack_offset)
    }
    gen.mcg.stream.emit_raw_bytes(code)
    gen.current_section_offset = gen.current_section_offset + (len(code) as int64)
    ""
}

func (gen* go_style_code_generator) gen_load(int dest_reg, int64 stack_offset, int size) string {
    code := int8[]()()
    if size == 8 {
        code = encode_load_memory_to_reg(dest_reg, 5 as int, stack_offset)
    } else if size == 4 {
        code = encode_load_memory_to_reg_32(dest_reg, 5 as int, stack_offset)
    }
    gen.mcg.stream.emit_raw_bytes(code)
    gen.current_section_offset = gen.current_section_offset + (len(code) as int64)
    ""
}

func (gen* go_style_code_generator) gen_main_function() string {
    func_name := "main"
    gen.gen_func_body(func_name, 0 as int64)
    gen.gen_load_const(60 as int64, 0)
    gen.gen_load_const(42 as int64, 7)
    syscall_code := encode_syscall()
    gen.mcg.stream.emit_raw_bytes(syscall_code)
    gen.current_section_offset = gen.current_section_offset + (len(syscall_code) as int64)
    gen.gen_func_epilogue(0 as int64)
    ""
}

func (gen* go_style_code_generator) gen_program_entry() int8[] {
    entry_code := int8[]()()
    entry_code = encode_jmp_direct("main")
    entry_code
}

func (gen* go_style_code_generator) compile_complete_program() string {
    gen.gen_main_function()
    ""
}

func encode_sub_imm_from_reg(int reg, int64 imm) int8[] {
    result := int8[]()()
    if imm == 0 {
        return result
    }
    if imm < 0x80000000 as int64 && imm > -0x80000000 as int64 {
        result = append(result, 0x48 as int8)
        result = append(result, 0x81 as int8)
        result = append(result, (0xc0 + (reg & 7)) as int8)
        i := 0
        for i < 4 {
            b := ((imm >> (i * 8)) & 0xff) as int8
            result = append(result, b)
            i = i + 1
        }
    } else {
        result = encode_mov_imm_to_reg(imm, 0)
        result = append_bytes(result, encode_sub_reg_from_reg(reg, 0))
    }
    result
}

func encode_add_imm_to_reg(int reg, int64 imm) int8[] {
    result := int8[]()()
    if imm == 0 {
        return result
    }
    if imm < 0x80000000 as int64 && imm > -0x80000000 as int64 {
        result = append(result, 0x48 as int8)
        result = append(result, 0x81 as int8)
        result = append(result, (0xc0 + (reg & 7)) as int8)
        i := 0
        for i < 4 {
            b := ((imm >> (i * 8)) & 0xff) as int8
            result = append(result, b)
            i = i + 1
        }
    }
    result
}

func encode_imul_reg_reg(int dest_reg, int src_reg) int8[] {
    result := int8[]()()
    result = append(result, 0x48 as int8)
    result = append(result, 0x0f as int8)
    result = append(result, 0xaf as int8)
    result = append(result, ((0xc0 + ((dest_reg & 7) << 3) + (src_reg & 7)) as int8))
    result
}

func encode_cmp_reg_reg(int left_reg, int right_reg) int8[] {
    result := int8[]()()
    result = append(result, 0x48 as int8)
    result = append(result, 0x39 as int8)
    result = append(result, ((0xc0 + ((right_reg & 7) << 3) + (left_reg & 7)) as int8))
    result
}

func encode_store_reg_to_memory(int src_reg, int base_reg, int64 offset) int8[] {
    result := int8[]()()
    result = append(result, 0x48 as int8)
    result = append(result, 0x89 as int8)
    if offset >= -128 as int64 && offset < 128 as int64 {
        result = append(result, ((0x40 + ((src_reg & 7) << 3) + (base_reg & 7)) as int8))
        result = append(result, (offset as int8))
    } else {
        result = append(result, ((0x80 + ((src_reg & 7) << 3) + (base_reg & 7)) as int8))
        i := 0
        for i < 4 {
            b := ((offset >> (i * 8)) & 0xff) as int8
            result = append(result, b)
            i = i + 1
        }
    }
    result
}

func encode_store_reg_to_memory_32(int src_reg, int base_reg, int64 offset) int8[] {
    result := int8[]()()
    result = append(result, 0x89 as int8)
    if offset >= -128 as int64 && offset < 128 as int64 {
        result = append(result, ((0x40 + ((src_reg & 7) << 3) + (base_reg & 7)) as int8))
        result = append(result, (offset as int8))
    } else {
        result = append(result, ((0x80 + ((src_reg & 7) << 3) + (base_reg & 7)) as int8))
        i := 0
        for i < 4 {
            b := ((offset >> (i * 8)) & 0xff) as int8
            result = append(result, b)
            i = i + 1
        }
    }
    result
}

func encode_load_memory_to_reg(int dest_reg, int base_reg, int64 offset) int8[] {
    result := int8[]()()
    result = append(result, 0x48 as int8)
    result = append(result, 0x8b as int8)
    if offset >= -128 as int64 && offset < 128 as int64 {
        result = append(result, ((0x40 + ((dest_reg & 7) << 3) + (base_reg & 7)) as int8))
        result = append(result, (offset as int8))
    } else {
        result = append(result, ((0x80 + ((dest_reg & 7) << 3) + (base_reg & 7)) as int8))
        i := 0
        for i < 4 {
            b := ((offset >> (i * 8)) & 0xff) as int8
            result = append(result, b)
            i = i + 1
        }
    }
    result
}

func encode_load_memory_to_reg_32(int dest_reg, int base_reg, int64 offset) int8[] {
    result := int8[]()()
    result = append(result, 0x8b as int8)
    if offset >= -128 as int64 && offset < 128 as int64 {
        result = append(result, ((0x40 + ((dest_reg & 7) << 3) + (base_reg & 7)) as int8))
        result = append(result, (offset as int8))
    } else {
        result = append(result, ((0x80 + ((dest_reg & 7) << 3) + (base_reg & 7)) as int8))
        i := 0
        for i < 4 {
            b := ((offset >> (i * 8)) & 0xff) as int8
            result = append(result, b)
            i = i + 1
        }
    }
    result
}

func encode_call_direct(string func_name) int8[] {
    result := int8[]()()
    result = append(result, 0xe8 as int8)
    result = append(result, 0x00 as int8)
    result = append(result, 0x00 as int8)
    result = append(result, 0x00 as int8)
    result = append(result, 0x00 as int8)
    result
}

func encode_jmp_direct(string target) int8[] {
    result := int8[]()()
    result = append(result, 0xe9 as int8)
    result = append(result, 0x00 as int8)
    result = append(result, 0x00 as int8)
    result = append(result, 0x00 as int8)
    result = append(result, 0x00 as int8)
    result
}
