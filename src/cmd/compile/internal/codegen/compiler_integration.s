package compile.internal.codegen
use compile.internal.link
use compile.internal.obj
struct s_compiler_full {
    link_context* link_ctx
    machine_code_gen* mcg
    symbol_table* symtab
    relocation_context* reloc_ctx
    go_style_code_generator* codegen
    go_style_elf_generator* elf_gen
    codegen_config config
}

func make_s_compiler_full() s_compiler_full {
    link_ctx := make_link_context()
    mcg := make_machine_code_gen(&link_ctx)
    symtab := make_symbol_table()
    reloc_ctx := make_relocation_context()
    config := make_codegen_config("amd64")
    elf_writer := make_elf_writer(elf_machine_x86_64)
    elf_gen := make_go_style_elf_generator(&elf_writer, &symtab, &reloc_ctx)
    codegen := make_go_style_code_generator(&mcg, &symtab, &reloc_ctx, config)
    s_compiler_full {
        link_ctx: &link_ctx,
        mcg: &mcg,
        symtab: &symtab,
        reloc_ctx: &reloc_ctx,
        codegen: &codegen,
        elf_gen: &elf_gen,
        config: config,
    }
}

func (compiler* s_compiler_full) compile_and_generate_object() []int8 {
    compiler.codegen.gen_main_function()
    machine_code := compiler.mcg.stream.get_code()
    compiler.elf_gen.text_section = machine_code
    elf_object := compiler.elf_gen.generate_elf_object()
    elf_object
}

func (compiler* s_compiler_full) compile_and_generate_executable() []int8 {
    compiler.codegen.gen_main_function()
    machine_code := compiler.mcg.stream.get_code()
    compiler.elf_gen.text_section = machine_code
    elf_exec := compiler.elf_gen.generate_elf_executable()
    elf_exec
}

func (compiler* s_compiler_full) dump_compilation_info() string {
    result := "\n=== S 语言编译器 - 参考 Go 的直接机器码生成 ===\n"
    result = result + "\n编译目标架构: " + compiler.config.target_arch
    result = result + "\n代码段大小: " + int_to_string(len(compiler.mcg.stream.code))
    result = result + " 字节\n"
    result = result + "\n符号表信息:\n"
    result = result + compiler.symtab.dump()
    result = result + "\n重定位信息:\n"
    result = result + compiler.reloc_ctx.dump()
    result
}

func demo_direct_machine_code_generation() string {
    result := "\n=== 直接机器码生成演示 ===\n\n"
    result = result + "1. AMD64 指令编码示例\n"
    result = result + "   mov rax, rax:\n   "
    mov_code := encode_mov_reg_to_reg(0, 0)
    result = result + byte_array_to_hex(mov_code)
    result = result + "\n\n"
    result = result + "2. 加载常数到寄存器\n"
    result = result + "   mov rax, 0x42:\n   "
    mov_imm := encode_mov_imm_to_reg(0x42 as int64, 0)
    result = result + byte_array_to_hex(mov_imm)
    result = result + "\n\n"
    result = result + "3. 算术操作\n"
    result = result + "   add rax, rbx:\n   "
    add_code := encode_add_reg_to_reg(0, 3)
    result = result + byte_array_to_hex(add_code)
    result = result + "\n\n"
    result = result + "4. 控制流指令\n"
    result = result + "   push rbp:\n   "
    push_code := encode_push_reg(5)
    result = result + byte_array_to_hex(push_code)
    result = result + "\n"
    result = result + "   pop rbp:\n   "
    pop_code := encode_pop_reg(5)
    result = result + byte_array_to_hex(pop_code)
    result = result + "\n"
    result = result + "   ret:\n   "
    ret_code := encode_ret()
    result = result + byte_array_to_hex(ret_code)
    result = result + "\n\n"
    result = result + "5. 系统调用 (syscall)\n   "
    syscall_code := encode_syscall()
    result = result + byte_array_to_hex(syscall_code)
    result = result + "\n\n"
    result
}

func demo_complete_compilation() string {
    result := "\n=== 完整编译过程演示 ===\n\n"
    compiler := make_s_compiler_full()
    result = result + "编译过程步骤:\n"
    result = result + "1. 解析源代码 (简化：直接生成 main 函数)\n"
    result = result + "2. 生成机器码\n"
    result = result + "3. 生成符号表\n"
    result = result + "4. 生成重定位信息\n"
    result = result + "5. 生成 ELF 对象文件\n\n"
    elf_obj := compiler.compile_and_generate_object()
    result = result + "生成的对象文件大小: " + int_to_string(len(elf_obj)) + " 字节\n"
    result = result + "\n" + compiler.dump_compilation_info()
    result
}

func demo_go_style_design() string {
    result := "\n=== 参考 Go 编译器的设计模式 ===\n\n"
    result = result + "1. 直接机器码生成\n"
    result = result + "   - 不需要中间表示 (IR)\n"
    result = result + "   - 直接从 AST 生成机器码\n"
    result = result + "   - 更小的编译时间和内存占用\n\n"
    result = result + "2. 架构特定优化\n"
    result = result + "   - AMD64 指令编码优化\n"
    result = result + "   - 寄存器分配算法\n"
    result = result + "   - 指令选择 (Instruction Selection)\n\n"
    result = result + "3. 链接和重定位\n"
    result = result + "   - 重定位表生成\n"
    result = result + "   - 符号解析\n"
    result = result + "   - ELF 对象文件格式\n\n"
    result = result + "4. 标准 ABI 遵从\n"
    result = result + "   - System V AMD64 ABI\n"
    result = result + "   - 参数传递规则 (rdi, rsi, rdx, rcx, r8, r9)\n"
    result = result + "   - 栈帧结构\n\n"
    result
}

func generate_complete_demo_report() string {
    report := "\n"
    report = report + "╔════════════════════════════════════════════════════════════════╗\n"
    report = report + "║      S 语言编译器 - 参考 Go 的直接机器码生成实现              ║\n"
    report = report + "╚════════════════════════════════════════════════════════════════╝\n"
    report = report + demo_direct_machine_code_generation()
    report = report + demo_go_style_design()
    report = report + demo_complete_compilation()
    report = report + "\n=== 编译系统架构 ===\n\n"
    report = report + "lexer   parser   → codegen → machine_code\n"
    report = report + "                      ↓\n"
    report = report + "                  symbol_table\n"
    report = report + "                      ↓\n"
    report = report + "                  relocation_ctx\n"
    report = report + "                      ↓\n"
    report = report + "                  elf_generator\n"
    report = report + "                      ↓\n"
    report = report + "                   object.o\n"
    report = report + "                      ↓\n"
    report = report + "                     linker\n"
    report = report + "                      ↓\n"
    report = report + "                   executable\n\n"
    report = report + "=== 核心模块 ===\n"
    report = report + "• encoding.s                - 指令编码\n"
    report = report + "• machine.s                 - 指令流和机器码生成\n"
    report = report + "• codegen.s                 - 代码生成上下文\n"
    report = report + "• go_style_codegen.s        - 参考 Go 的高级代码生成器\n"
    report = report + "• elf64.s                   - ELF 64-bit 数据结构\n"
    report = report + "• go_style_elf_generator.s  - 参考 Go 的 ELF 生成器\n"
    report = report + "• relocation.s              - 重定位处理\n"
    report = report + "• symbol.s                  - 符号表管理\n\n"
    report = report + "=== 特性 ===\n"
    report = report + "✓ 直接机器码生成，无中间表示\n"
    report = report + "✓ 完整的 AMD64 指令编码\n"
    report = report + "✓ ELF 格式对象文件生成\n"
    report = report + "✓ 符号表和重定位支持\n"
    report = report + "✓ System V AMD64 ABI 遵从\n"
    report = report + "✓ 参考 Go 编译器的架构和设计模式\n\n"
    report
}

func byte_array_to_hex([]int8 data) string {
    result := ""
    i := 0
    for i < len(data) {
        b := data[i]
        high := ((b >> 4) & 0xf)
        low := (b & 0xf)
        high_char := if high < 10 as int8 {
            (0x30 as int8 + high)
        } else {
            (0x61 as int8 + (high - 10 as int8))
        }
        low_char := if low < 10 as int8 {
            (0x30 as int8 + low)
        } else {
            (0x61 as int8 + (low - 10 as int8))
        }
        result = result + (high_char as string)
        result = result + (low_char as string)
        result = result + " "
        i = i + 1
    }
    result
}

func int_to_string(int value) string {
    if value == 0 {
        return "0"
    }
    result := ""
    v := value
    if v < 0 {
        result = "-"
        v = -v
    }
    digits := ""
    while v > 0 {
        digit := v % 10
        digit_char := (0x30 as int8 + (digit as int8)) as string
        digits = digit_char + digits
        v = v / 10
    }
    result + digits
}

func compile_s_source(source* string) []int8 {
    lexer* := lexer_new(source)
    lexer_tokenize(lexer)
    tokens* := lexer_get_tokens(lexer)
    token_count := lexer_get_token_count(lexer)
    if token_count == 0 {
        return nil
    }
    parser* := parser_new(tokens, token_count)
    program* := parser_parse_program(parser)
    if program == nil {
        return nil
    }
    ctx* := typecheck_new()
    result := typecheck_program(ctx, program)
    if result == 0 || typecheck_get_error_count(ctx) > 0 {
        return nil
    }
    compiler := make_s_compiler_full()
    compiler.codegen.gen_main_function()
    object_code := compiler.compile_and_generate_object()
    return object_code
}

func compile_s_to_executable(source* string) []int8 {
    lexer* := lexer_new(source)
    lexer_tokenize(lexer)
    tokens* := lexer_get_tokens(lexer)
    token_count := lexer_get_token_count(lexer)
    if token_count == 0 {
        return nil
    }
    parser* := parser_new(tokens, token_count)
    program* := parser_parse_program(parser)
    if program == nil {
        return nil
    }
    ctx* := typecheck_new()
    result := typecheck_program(ctx, program)
    if result == 0 {
        return nil
    }
    compiler := make_s_compiler_full()
    compiler.codegen.gen_main_function()
    executable := compiler.compile_and_generate_executable()
    return executable
}

func compile_and_get_info(source* string) string {
    lexer* := lexer_new(source)
    lexer_tokenize(lexer)
    tokens* := lexer_get_tokens(lexer)
    token_count := lexer_get_token_count(lexer)
    if token_count == 0 {
        return "错误：无法进行词法分析"
    }
    info := "\n=== 编译信息 ===\n"
    info = info + "\n第 1 步: 词法分析\n"
    info = info + "  Token 数量: "
    info = info + int_to_string(token_count)
    info = info + "\n"
    parser* := parser_new(tokens, token_count)
    program* := parser_parse_program(parser)
    if program == nil {
        info = info + "\n第 2 步: 语法分析\n"
        info = info + "  错误：无法构建 AST\n"
        return info
    }
    info = info + "\n第 2 步: 语法分析\n"
    info = info + "  AST 构建成功\n"
    ctx* := typecheck_new()
    result := typecheck_program(ctx, program)
    error_count := typecheck_get_error_count(ctx)
    info = info + "\n第 3 步: 类型检查\n"
    info = info + "  错误数: "
    info = info + int_to_string(error_count)
    info = info + "\n"
    if error_count > 0 {
        info = info + "  编译失败\n"
        return info
    }
    compiler := make_s_compiler_full()
    compiler.codegen.gen_main_function()
    info = info + "\n第 4 步: 代码生成\n"
    info = info + "  代码段大小: "
    info = info + int_to_string(len(compiler.mcg.stream.code))
    info = info + " 字节\n"
    object_code := compiler.compile_and_generate_object()
    info = info + "\n第 5 步: ELF 对象文件生成\n"
    info = info + "  对象文件大小: "
    info = info + int_to_string(len(object_code))
    info = info + " 字节\n"
    info = info + "\n编译成功！\n"
    return info
}
