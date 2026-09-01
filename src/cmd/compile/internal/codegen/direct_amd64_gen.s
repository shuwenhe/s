package compile.internal.codegen

use compile.internal.ast
use compile.internal.link
use compile.internal.obj
use compile.internal.types

// Direct AMD64 Machine Code Generator - 参考 Go 的直接代码生成
// 直接从 AST 生成 AMD64 机器码，无需中间表示 (IR/SSA)
// 支持自举编译

// AMD64 寄存器编码
const REG_RAX = 0
const REG_RCX = 1
const REG_RDX = 2
const REG_RBX = 3
const REG_RSP = 4
const REG_RBP = 5
const REG_RSI = 6
const REG_RDI = 7
const REG_R8  = 8
const REG_R9  = 9
const REG_R10 = 10
const REG_R11 = 11
const REG_R12 = 12
const REG_R13 = 13
const REG_R14 = 14
const REG_R15 = 15

// AMD64 操作码
const OP_ADD_IMM_R64 = 0x4881  // add r64, imm32
const OP_SUB_IMM_R64 = 0x4881  // sub r64, imm32
const OP_MOV_IMM_R64 = 0x48B8  // mov r64, imm64
const OP_MOV_R_R64   = 0x4889  // mov r64, r64
const OP_PUSH_R64    = 0x50    // push r64
const OP_POP_R64     = 0x58    // pop r64
const OP_RET         = 0xC3    // ret
const OP_CALL_REL32  = 0xE8    // call rel32
const OP_JMP_REL32   = 0xE9    // jmp rel32
const OP_JE_REL32    = 0x840F  // je rel32 (2-byte opcode)
const OP_JNE_REL32   = 0x850F  // jne rel32
const OP_CMP_R_R64   = 0x4839  // cmp r64, r64
const OP_TEST_R_R64  = 0x4885  // test r64, r64

// 寄存器分配上下文
struct register_allocator {
    int[] free_regs
    int[] allocated
    int reg_count
    int current_temp
}

func make_register_allocator() register_allocator {
    // 可用的通用寄存器（不包括 RSP 和 RBP）
    free_regs := int[]()
    free_regs = append(free_regs, REG_RAX)
    free_regs = append(free_regs, REG_RCX)
    free_regs = append(free_regs, REG_RDX)
    free_regs = append(free_regs, REG_RSI)
    free_regs = append(free_regs, REG_RDI)
    free_regs = append(free_regs, REG_R8)
    free_regs = append(free_regs, REG_R9)
    free_regs = append(free_regs, REG_R10)
    free_regs = append(free_regs, REG_R11)
    free_regs = append(free_regs, REG_R12)
    free_regs = append(free_regs, REG_R13)
    free_regs = append(free_regs, REG_R14)
    
    register_allocator {
        free_regs: free_regs,
        allocated: int[](),
        reg_count: 12,
        current_temp: 0,
    }
}

// 代码生成上下文
struct amd64_code_gen {
    machine_code_gen* mcg
    symbol_table* symtab
    relocation_context* reloc_ctx
    codegen_config config
    register_allocator reg_alloc
    
    // 当前函数的上下文
    string current_func_name
    int64 stack_depth
    int64 max_stack_depth
    int64 function_start_offset
    
    // 标签管理
    int label_counter
    
    // 临时变量栈
    int64[] temp_locations
}

func make_amd64_code_gen(
    machine_code_gen* mcg,
    symbol_table* symtab,
    relocation_context* reloc_ctx,
    codegen_config cfg
) amd64_code_gen {
    amd64_code_gen {
        mcg: mcg,
        symtab: symtab,
        reloc_ctx: reloc_ctx,
        config: cfg,
        reg_alloc: make_register_allocator(),
        current_func_name: "",
        stack_depth: 0 as int64,
        max_stack_depth: 0 as int64,
        function_start_offset: 0 as int64,
        label_counter: 0,
        temp_locations: int64[](),
    }
}

// 分配寄存器
func (gen* amd64_code_gen) alloc_reg() int {
    if gen.reg_alloc.reg_count > 0 {
        reg := gen.reg_alloc.free_regs[0]
        gen.reg_alloc.free_regs = gen.reg_alloc.free_regs[1:]
        gen.reg_alloc.reg_count = gen.reg_alloc.reg_count - 1
        return reg
    }
    // 临时寄存器不足，使用栈上的临时位置
    return -1
}

// 释放寄存器
func (gen* amd64_code_gen) free_reg(int reg) {
    if reg >= 0 {
        gen.reg_alloc.free_regs = append(gen.reg_alloc.free_regs, reg)
        gen.reg_alloc.reg_count = gen.reg_alloc.reg_count + 1
    }
}

// ============================================================
// 原始指令生成
// ============================================================

// mov r64, imm64
func encode_mov_imm64_to_r64(int reg, int64 value) int8[] {
    code := int8[]()
    
    if reg >= REG_R8 {
        code = append(code, 0x49 as int8)  // REX.B
    } else {
        code = append(code, 0x48 as int8)  // REX.W
    }
    
    base := REG_RAX
    if reg >= REG_R8 {
        base = reg - 8
    } else {
        base = reg
    }
    
    code = append(code, (0xB8 + base) as int8)
    
    // Append 64-bit immediate in little-endian
    code = append(code, (value & 0xFF) as int8)
    code = append(code, ((value >> 8) & 0xFF) as int8)
    code = append(code, ((value >> 16) & 0xFF) as int8)
    code = append(code, ((value >> 24) & 0xFF) as int8)
    code = append(code, ((value >> 32) & 0xFF) as int8)
    code = append(code, ((value >> 40) & 0xFF) as int8)
    code = append(code, ((value >> 48) & 0xFF) as int8)
    code = append(code, ((value >> 56) & 0xFF) as int8)
    
    code
}

// mov r64, r64
func encode_mov_r64_to_r64(int dst, int src) int8[] {
    code := int8[]()
    
    // REX prefix
    rex := 0x48 as int8
    if dst >= REG_R8 {
        rex = (rex | 0x04) as int8
    }
    if src >= REG_R8 {
        rex = (rex | 0x01) as int8
    }
    code = append(code, rex)
    
    // Opcode + ModRM
    code = append(code, 0x89 as int8)
    
    dst_reg := dst % 8
    src_reg := src % 8
    modrm := ((0x03 << 6) | (src_reg << 3) | dst_reg) as int8
    code = append(code, modrm)
    
    code
}

// push r64
func encode_push_r64(int reg) int8[] {
    code := int8[]()
    
    if reg >= REG_R8 {
        code = append(code, 0x41 as int8)  // REX.B
    }
    
    base := reg % 8
    code = append(code, (0x50 + base) as int8)
    
    code
}

// pop r64
func encode_pop_r64(int reg) int8[] {
    code := int8[]()
    
    if reg >= REG_R8 {
        code = append(code, 0x41 as int8)  // REX.B
    }
    
    base := reg % 8
    code = append(code, (0x58 + base) as int8)
    
    code
}

// add r64, imm32
func encode_add_imm32_to_r64(int reg, int32 value) int8[] {
    code := int8[]()
    
    rex := 0x48 as int8
    if reg >= REG_R8 {
        rex = (rex | 0x01) as int8
    }
    code = append(code, rex)
    
    // If reg == RSP, use 81 /0
    if reg == REG_RSP || reg == REG_R8 + (REG_RSP - REG_RAX) {
        code = append(code, 0x81 as int8)
        
        modrm := ((0x03 << 6) | (0x00 << 3) | (reg % 8)) as int8
        code = append(code, modrm)
    } else {
        code = append(code, 0x81 as int8)
        modrm := ((0x03 << 6) | (0x00 << 3) | (reg % 8)) as int8
        code = append(code, modrm)
    }
    
    code = append(code, (value & 0xFF) as int8)
    code = append(code, ((value >> 8) & 0xFF) as int8)
    code = append(code, ((value >> 16) & 0xFF) as int8)
    code = append(code, ((value >> 24) & 0xFF) as int8)
    
    code
}

// sub r64, imm32
func encode_sub_imm32_from_r64(int reg, int32 value) int8[] {
    code := int8[]()
    
    rex := 0x48 as int8
    if reg >= REG_R8 {
        rex = (rex | 0x01) as int8
    }
    code = append(code, rex)
    
    code = append(code, 0x81 as int8)
    modrm := ((0x03 << 6) | (0x05 << 3) | (reg % 8)) as int8
    code = append(code, modrm)
    
    code = append(code, (value & 0xFF) as int8)
    code = append(code, ((value >> 8) & 0xFF) as int8)
    code = append(code, ((value >> 16) & 0xFF) as int8)
    code = append(code, ((value >> 24) & 0xFF) as int8)
    
    code
}

// ret
func encode_ret() int8[] {
    code := int8[]()
    code = append(code, 0xC3 as int8)
    code
}

// call rel32
func encode_call_rel32(int32 rel_offset) int8[] {
    code := int8[]()
    code = append(code, 0xE8 as int8)
    
    code = append(code, (rel_offset & 0xFF) as int8)
    code = append(code, ((rel_offset >> 8) & 0xFF) as int8)
    code = append(code, ((rel_offset >> 16) & 0xFF) as int8)
    code = append(code, ((rel_offset >> 24) & 0xFF) as int8)
    
    code
}

// jmp rel32
func encode_jmp_rel32(int32 rel_offset) int8[] {
    code := int8[]()
    code = append(code, 0xE9 as int8)
    
    code = append(code, (rel_offset & 0xFF) as int8)
    code = append(code, ((rel_offset >> 8) & 0xFF) as int8)
    code = append(code, ((rel_offset >> 16) & 0xFF) as int8)
    code = append(code, ((rel_offset >> 24) & 0xFF) as int8)
    
    code
}

// cmp r64, r64
func encode_cmp_r64_r64(int dst, int src) int8[] {
    code := int8[]()
    
    rex := 0x48 as int8
    if dst >= REG_R8 {
        rex = (rex | 0x04) as int8
    }
    if src >= REG_R8 {
        rex = (rex | 0x01) as int8
    }
    code = append(code, rex)
    
    code = append(code, 0x39 as int8)
    modrm := ((0x03 << 6) | (src % 8 << 3) | (dst % 8)) as int8
    code = append(code, modrm)
    
    code
}

// ============================================================
// 高级代码生成 (AST → 机器码)
// ============================================================

// 生成函数序言（prologue）
func (gen* amd64_code_gen) gen_prologue(int64 stack_size) {
    // push rbp
    code := encode_push_r64(REG_RBP)
    gen.mcg.stream.emit_raw_bytes(code)
    
    // mov rbp, rsp
    code = encode_mov_r64_to_r64(REG_RBP, REG_RSP)
    gen.mcg.stream.emit_raw_bytes(code)
    
    // sub rsp, stack_size (对齐到 16 字节边界)
    aligned_stack := ((stack_size + 15) / 16) * 16
    if aligned_stack > 0 {
        code = encode_sub_imm32_from_r64(REG_RSP, (aligned_stack & 0xFFFFFFFF) as int32)
        gen.mcg.stream.emit_raw_bytes(code)
    }
    
    gen.stack_depth = 0 as int64
    gen.max_stack_depth = aligned_stack
}

// 生成函数结尾（epilogue）
func (gen* amd64_code_gen) gen_epilogue() {
    // add rsp, stack_size
    if gen.max_stack_depth > 0 {
        code := encode_add_imm32_to_r64(REG_RSP, (gen.max_stack_depth & 0xFFFFFFFF) as int32)
        gen.mcg.stream.emit_raw_bytes(code)
    }
    
    // pop rbp
    code := encode_pop_r64(REG_RBP)
    gen.mcg.stream.emit_raw_bytes(code)
    
    // ret
    code = encode_ret()
    gen.mcg.stream.emit_raw_bytes(code)
}

// 从 AST 函数声明生成代码
func (gen* amd64_code_gen) gen_func_from_ast(ast_func_decl* func) {
    gen.current_func_name = func.name
    gen.function_start_offset = gen.mcg.get_current_offset()
    
    // 估计堆栈需求
    stack_size := (64 as int64)  // 基础堆栈大小
    
    gen.gen_prologue(stack_size)
    
    // 生成函数体
    if func.body != nil {
        gen.gen_block_from_ast(func.body)
    }
    
    gen.gen_epilogue()
}

// 从 AST 块生成代码
func (gen* amd64_code_gen) gen_block_from_ast(ast_block* block) {
    if block == nil {
        return
    }
    
    // 遍历块中的所有语句
    for i := 0; i < len(block.statements); i = i + 1 {
        stmt := block.statements[i]
        gen.gen_stmt_from_ast(stmt)
    }
}

// 从 AST 语句生成代码
func (gen* amd64_code_gen) gen_stmt_from_ast(ast_stmt* stmt) {
    if stmt == nil {
        return
    }
    
    // 根据语句类型分发
    if stmt.kind == AST_RETURN_STMT {
        gen.gen_return_stmt(stmt)
    } else if stmt.kind == AST_IF_STMT {
        gen.gen_if_stmt(stmt)
    } else if stmt.kind == AST_FOR_STMT {
        gen.gen_for_stmt(stmt)
    } else if stmt.kind == AST_EXPR_STMT {
        if stmt.expression != nil {
            gen.gen_expr_from_ast(stmt.expression)
        }
    } else if stmt.kind == AST_VAR_DECL {
        gen.gen_var_decl(stmt)
    }
}

// 生成 return 语句
func (gen* amd64_code_gen) gen_return_stmt(ast_stmt* stmt) {
    if stmt.expression != nil {
        // 计算表达式值到 RAX（返回值寄存器）
        result_reg := gen.gen_expr_from_ast(stmt.expression)
        if result_reg != REG_RAX && result_reg >= 0 {
            // mov rax, result_reg
            code := encode_mov_r64_to_r64(REG_RAX, result_reg)
            gen.mcg.stream.emit_raw_bytes(code)
            gen.free_reg(result_reg)
        }
    } else {
        // 无返回值，设置 RAX = 0
        code := encode_mov_imm64_to_r64(REG_RAX, 0 as int64)
        gen.mcg.stream.emit_raw_bytes(code)
    }
    
    gen.gen_epilogue()
}

// 生成 if 语句
func (gen* amd64_code_gen) gen_if_stmt(ast_stmt* stmt) {
    gen.label_counter = gen.label_counter + 1
    else_label := gen.label_counter
    gen.label_counter = gen.label_counter + 1
    end_label := gen.label_counter
    
    // 计算条件
    cond_reg := gen.gen_expr_from_ast(stmt.condition)
    
    // 比较 cond_reg 与 0
    code := encode_cmp_r64_r64(cond_reg, cond_reg)  // cmp reg, reg (结果 = 0 时设置零标志)
    gen.mcg.stream.emit_raw_bytes(code)
    
    // 如果为假，跳转到 else_label
    // je else_label
    code = encode_call_rel32(0)  // 占位符，后续需要重定位
    gen.mcg.stream.emit_raw_bytes(code)
    
    gen.free_reg(cond_reg)
    
    // 生成 then 分支
    if stmt.then_branch != nil {
        gen.gen_block_from_ast(stmt.then_branch)
    }
    
    // 生成 else 分支
    if stmt.else_branch != nil {
        // jmp end_label
        code = encode_jmp_rel32(0)  // 占位符
        gen.mcg.stream.emit_raw_bytes(code)
        
        gen.gen_block_from_ast(stmt.else_branch)
    }
}

// 生成 for 语句
func (gen* amd64_code_gen) gen_for_stmt(ast_stmt* stmt) {
    gen.label_counter = gen.label_counter + 1
    loop_label := gen.label_counter
    gen.label_counter = gen.label_counter + 1
    end_label := gen.label_counter
    
    // 初始化
    if stmt.init != nil {
        gen.gen_stmt_from_ast(stmt.init)
    }
    
    // 循环条件检查
    // jmp loop_check
    
    // 循环体
    // loop_label:
    if stmt.body != nil {
        gen.gen_block_from_ast(stmt.body)
    }
    
    // 递增
    if stmt.post != nil {
        gen.gen_stmt_from_ast(stmt.post)
    }
    
    // 条件检查
    // loop_check:
    if stmt.condition != nil {
        cond_reg := gen.gen_expr_from_ast(stmt.condition)
        
        // cmp cond_reg, 0
        code := encode_cmp_r64_r64(cond_reg, cond_reg)
        gen.mcg.stream.emit_raw_bytes(code)
        
        // jne loop_label (如果非零则跳转回循环开始)
        code = encode_call_rel32(0)  // 占位符
        gen.mcg.stream.emit_raw_bytes(code)
        
        gen.free_reg(cond_reg)
    }
}

// 生成表达式代码，返回结果寄存器编号
func (gen* amd64_code_gen) gen_expr_from_ast(ast_expr* expr) int {
    if expr == nil {
        return -1
    }
    
    if expr.kind == AST_INTEGER_LITERAL {
        // mov reg, imm64
        reg := gen.alloc_reg()
        value := expr.int_value
        code := encode_mov_imm64_to_r64(reg, value)
        gen.mcg.stream.emit_raw_bytes(code)
        return reg
    } else if expr.kind == AST_BINARY_OP {
        left_reg := gen.gen_expr_from_ast(expr.left)
        right_reg := gen.gen_expr_from_ast(expr.right)
        
        if expr.op == 0x2B {  // '+' operator
            // add left_reg, right_reg
            code := encode_add_imm32_to_r64(left_reg, 0)  // 简化版本
            gen.mcg.stream.emit_raw_bytes(code)
            gen.free_reg(right_reg)
            return left_reg
        }
        
        return left_reg
    } else if expr.kind == AST_FUNC_CALL {
        // 函数调用
        // 设置参数到寄存器 (System V AMD64 ABI)
        // 第一个参数: RDI
        // 第二个参数: RSI
        // 第三个参数: RDX
        // ...
        
        return REG_RAX  // 返回值在 RAX
    }
    
    return -1
}

// 生成变量声明
func (gen* amd64_code_gen) gen_var_decl(ast_stmt* stmt) {
    // 为变量分配栈空间
    if stmt.name != "" {
        gen.stack_depth = gen.stack_depth + 8 as int64
        if gen.stack_depth > gen.max_stack_depth {
            gen.max_stack_depth = gen.stack_depth
        }
    }
}

// ============================================================
// 主要入口函数
// ============================================================

// 从完整的 AST 生成目标文件
func (gen* amd64_code_gen) gen_from_ast_program(ast_program* prog) string {
    if prog == nil {
        return "error: null program"
    }
    
    // 添加程序作为符号
    gen.symtab.add_symbol(
        "main",
        symbol_bind_global,
        symbol_type_func,
        gen.mcg.get_current_offset(),
        0 as int64,
        1
    )
    
    // 生成所有函数
    for i := 0; i < len(prog.functions); i = i + 1 {
        func := prog.functions[i]
        gen.gen_func_from_ast(func)
    }
    
    ""
}
