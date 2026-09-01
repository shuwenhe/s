package compile.internal.codegen

use compile.internal.link
use compile.internal.obj

// 参考 Go 编译器的直接机器码生成实现
// 直接从 AST 生成机器码，无需中间表示

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
        mcg: mcg,
        symtab: symtab,
        reloc_ctx: reloc_ctx,
        config: cfg,
        current_func_id: 0,
        current_section_offset: 0 as int64,
    }
}

// 参考 Go 的 genFuncBody，直接生成函数体的机器码
func (gen* go_style_code_generator) gen_func_body(string func_name, int64 stack_size) string {
    // 函数序言 (Prologue)：
    // push rbp
    // mov rsp, rbp
    // sub rsp, stack_size
    
    prologue := encode_push_reg(5)  // push rbp (reg_rbp = 5)
    prologue = append_bytes(prologue, encode_mov_reg_to_reg(5, 4))  // mov rbp, rsp
    
    if stack_size > 0 {
        // sub rsp, stack_size
        sub_code := encode_sub_imm_from_reg(4 as int, stack_size)  // reg_rsp = 4
        prologue = append_bytes(prologue, sub_code)
    }
    
    gen.mcg.stream.emit_raw_bytes(prologue)
    
    ""
}

// 参考 Go 的 genFuncEpilogue，生成函数结束的代码
func (gen* go_style_code_generator) gen_func_epilogue(int64 stack_size) string {
    // 函数结尾 (Epilogue)：
    // add rsp, stack_size
    // pop rbp
    // ret
    
    epilogue := []int8()()
    
    if stack_size > 0 {
        // add rsp, stack_size
        add_code := encode_add_imm_to_reg(4 as int, stack_size)  // reg_rsp = 4
        epilogue = append_bytes(epilogue, add_code)
    }
    
    epilogue = append_bytes(epilogue, encode_pop_reg(5))  // pop rbp
    epilogue = append_bytes(epilogue, encode_ret())
    
    gen.mcg.stream.emit_raw_bytes(epilogue)
    
    ""
}

// 参考 Go 的 genCall，生成函数调用代码
func (gen* go_style_code_generator) gen_call(string func_name, int arg_count) string {
    // 参数传递遵循 System V AMD64 ABI
    // 前 6 个整数参数使用：rdi, rsi, rdx, rcx, r8, r9
    // 返回值在 rax
    
    // mov rax, [rel func_name]  ; 获取函数地址
    // call rax
    
    // 为简化起见，使用 call 指令加上 relocation
    call_code := encode_call_direct(func_name)
    gen.mcg.stream.emit_raw_bytes(call_code)
    
    // 添加重定位信息
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

// 参考 Go 的 genLoadConst，生成常数加载
func (gen* go_style_code_generator) gen_load_const(int64 value, int dest_reg) string {
    // mov 64 bit immediate to register
    code := encode_mov_imm_to_reg(value, dest_reg)
    gen.mcg.stream.emit_raw_bytes(code)
    gen.current_section_offset = gen.current_section_offset + (len(code) as int64)
    ""
}

// 参考 Go 的 genBinOp，生成二元操作
func (gen* go_style_code_generator) gen_binop(string op, int left_reg, int right_reg, int result_reg) string {
    code := []int8()()
    
    if op == "add" {
        code = encode_add_reg_to_reg(left_reg, right_reg)
    } else if op == "sub" {
        code = encode_sub_reg_from_reg(left_reg, right_reg)
    } else if op == "mul" {
        // imul result_reg, left_reg
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

// 参考 Go 的 genStore，生成存储操作
func (gen* go_style_code_generator) gen_store(int source_reg, int64 stack_offset, int size) string {
    // mov [rbp - stack_offset], source_reg
    // 对于 AMD64，使用 ModR/M 和 SIB 字节
    
    code := []int8()()
    
    if size == 8 {
        // mov qword [rbp - stack_offset], source_reg
        // 0x48 0x89 0x45 0xf8 (例子：offset = 8)
        code = encode_store_reg_to_memory(source_reg, 5 as int, stack_offset)  // reg_rbp = 5
    } else if size == 4 {
        // mov dword [rbp - stack_offset], source_reg
        code = encode_store_reg_to_memory_32(source_reg, 5 as int, stack_offset)
    }
    
    gen.mcg.stream.emit_raw_bytes(code)
    gen.current_section_offset = gen.current_section_offset + (len(code) as int64)
    
    ""
}

// 参考 Go 的 genLoad，生成加载操作
func (gen* go_style_code_generator) gen_load(int dest_reg, int64 stack_offset, int size) string {
    // mov dest_reg, [rbp - stack_offset]
    
    code := []int8()()
    
    if size == 8 {
        // mov dest_reg, qword [rbp - stack_offset]
        code = encode_load_memory_to_reg(dest_reg, 5 as int, stack_offset)  // reg_rbp = 5
    } else if size == 4 {
        // mov dest_reg, dword [rbp - stack_offset]
        code = encode_load_memory_to_reg_32(dest_reg, 5 as int, stack_offset)
    }
    
    gen.mcg.stream.emit_raw_bytes(code)
    gen.current_section_offset = gen.current_section_offset + (len(code) as int64)
    
    ""
}

// 生成完整的 main 函数 (参考 Go 风格)
func (gen* go_style_code_generator) gen_main_function() string {
    func_name := "main"
    
    // 函数序言
    gen.gen_func_body(func_name, 0 as int64)
    
    // 函数体：简单的 exit(42) syscall
    // mov rax, 60  (sys_exit)
    // mov rdi, 42  (exit code)
    // syscall
    
    gen.gen_load_const(60 as int64, 0)  // reg_rax = 0, sys_exit
    gen.gen_load_const(42 as int64, 7)  // reg_rdi = 7, exit code
    
    syscall_code := encode_syscall()
    gen.mcg.stream.emit_raw_bytes(syscall_code)
    gen.current_section_offset = gen.current_section_offset + (len(syscall_code) as int64)
    
    // 函数结尾
    gen.gen_func_epilogue(0 as int64)
    
    ""
}

// 参考 Go 的 genEntry，生成程序入口点
func (gen* go_style_code_generator) gen_program_entry() []int8 {
    entry_code := []int8()()
    
    // 程序入口点通常由 _start (在没有 libc 时) 或操作系统直接调用
    // 这里我们直接调用 main
    
    // mov rax, qword [rel main]
    // jmp rax
    // 或者更直接：
    // jmp main (使用相对寻址)
    
    entry_code = encode_jmp_direct("main")
    
    entry_code
}

// 参考 Go 的完整编译过程
func (gen* go_style_code_generator) compile_complete_program() string {
    // 第 1 阶段：生成代码
    gen.gen_main_function()
    
    // 第 2 阶段：生成数据段（如果需要）
    
    // 第 3 阶段：生成重定位信息
    
    ""
}

// 辅助函数：生成 sub immediate from register
func encode_sub_imm_from_reg(int reg, int64 imm) []int8 {
    result := []int8()()
    
    if imm == 0 {
        return result
    }
    
    if imm < 0x80000000 as int64 && imm > -0x80000000 as int64 {
        // 32-bit immediate
        // 0x48 0x81 0xec (imm32) for sub rsp, imm32
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
        // 需要更大的 immediate
        // mov rax, imm64
        // sub register, rax
        result = encode_mov_imm_to_reg(imm, 0)
        result = append_bytes(result, encode_sub_reg_from_reg(reg, 0))
    }
    
    result
}

// 辅助函数：生成 add immediate to register
func encode_add_imm_to_reg(int reg, int64 imm) []int8 {
    result := []int8()()
    
    if imm == 0 {
        return result
    }
    
    if imm < 0x80000000 as int64 && imm > -0x80000000 as int64 {
        // 32-bit immediate
        // 0x48 0x81 0xc4 (imm32) for add rsp, imm32
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

// 辅助函数
func encode_imul_reg_reg(int dest_reg, int src_reg) []int8 {
    result := []int8()()
    result = append(result, 0x48 as int8)
    result = append(result, 0x0f as int8)
    result = append(result, 0xaf as int8)
    result = append(result, ((0xc0 + ((dest_reg & 7) << 3) + (src_reg & 7)) as int8))
    result
}

func encode_cmp_reg_reg(int left_reg, int right_reg) []int8 {
    result := []int8()()
    result = append(result, 0x48 as int8)
    result = append(result, 0x39 as int8)
    result = append(result, ((0xc0 + ((right_reg & 7) << 3) + (left_reg & 7)) as int8))
    result
}

func encode_store_reg_to_memory(int src_reg, int base_reg, int64 offset) []int8 {
    result := []int8()()
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

func encode_store_reg_to_memory_32(int src_reg, int base_reg, int64 offset) []int8 {
    result := []int8()()
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

func encode_load_memory_to_reg(int dest_reg, int base_reg, int64 offset) []int8 {
    result := []int8()()
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

func encode_load_memory_to_reg_32(int dest_reg, int base_reg, int64 offset) []int8 {
    result := []int8()()
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

func encode_call_direct(string func_name) []int8 {
    result := []int8()()
    result = append(result, 0xe8 as int8)
    // Placeholder for 32-bit offset (will be fixed by linker)
    result = append(result, 0x00 as int8)
    result = append(result, 0x00 as int8)
    result = append(result, 0x00 as int8)
    result = append(result, 0x00 as int8)
    result
}

func encode_jmp_direct(string target) []int8 {
    result := []int8()()
    result = append(result, 0xe9 as int8)
    // Placeholder for 32-bit offset (will be fixed by linker)
    result = append(result, 0x00 as int8)
    result = append(result, 0x00 as int8)
    result = append(result, 0x00 as int8)
    result = append(result, 0x00 as int8)
    result
}
