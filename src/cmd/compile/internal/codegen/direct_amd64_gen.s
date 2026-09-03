package compile.internal.codegen
use compile.internal.ast
use compile.internal.link
use compile.internal.obj
use compile.internal.types
const reg_rax = 0
const reg_rcx = 1
const reg_rdx = 2
const reg_rbx = 3
const reg_rsp = 4
const reg_rbp = 5
const reg_rsi = 6
const reg_rdi = 7
const reg_r8  = 8
const reg_r9  = 9
const reg_r10 = 10
const reg_r11 = 11
const reg_r12 = 12
const reg_r13 = 13
const reg_r14 = 14
const reg_r15 = 15
const op_add_imm_r64 = 0x4881
const op_sub_imm_r64 = 0x4881
const op_mov_imm_r64 = 0x48_b8
const op_mov_r_r64   = 0x4889
const op_push_r64    = 0x50
const op_pop_r64     = 0x58
const op_ret         = 0x_c3
const op_call_rel32  = 0x_e8
const op_jmp_rel32   = 0x_e9
const op_je_rel32    = 0x840_f
const op_jne_rel32   = 0x850_f
const op_cmp_r_r64   = 0x4839
const op_test_r_r64  = 0x4885
struct register_allocator {
    []int free_regs
    []int allocated
    int reg_count
    int current_temp
}

func make_register_allocator() register_allocator {
    free_regs := []int()
    free_regs = append(free_regs, reg_rax)
    free_regs = append(free_regs, reg_rcx)
    free_regs = append(free_regs, reg_rdx)
    free_regs = append(free_regs, reg_rsi)
    free_regs = append(free_regs, reg_rdi)
    free_regs = append(free_regs, reg_r8)
    free_regs = append(free_regs, reg_r9)
    free_regs = append(free_regs, reg_r10)
    free_regs = append(free_regs, reg_r11)
    free_regs = append(free_regs, reg_r12)
    free_regs = append(free_regs, reg_r13)
    free_regs = append(free_regs, reg_r14)
    register_allocator {
        free_regs: free_regs, allocated []int(), reg_count 12, current_temp 0,
    }
}

struct amd64_code_gen {
    machine_code_gen* mcg
    symbol_table* symtab
    relocation_context* reloc_ctx
    codegen_config config
    register_allocator reg_alloc
    string current_func_name
    int64 stack_depth
    int64 max_stack_depth
    int64 function_start_offset
    int label_counter
    int64[] temp_locations
}

func make_amd64_code_gen(
    machine_code_gen* mcg,
    symbol_table* symtab,
    relocation_context* reloc_ctx,
    codegen_config cfg
) amd64_code_gen {
    amd64_code_gen {
        mcg: mcg, symtab symtab, reloc_ctx reloc_ctx, config cfg, reg_alloc make_register_allocator(),
        current_func_name: "", stack_depth 0 as int64, max_stack_depth 0 as int64, function_start_offset 0 as int64, label_counter 0, temp_locations int64[](),
    }
}

func (gen* amd64_code_gen) alloc_reg() int {
    if gen.reg_alloc.reg_count > 0 {
        reg := gen.reg_alloc.free_regs[0]
        gen.reg_alloc.free_regs = gen.reg_alloc.free_regs[1:]
        gen.reg_alloc.reg_count = gen.reg_alloc.reg_count - 1
        return reg
    }
    return -1
}

func (gen* amd64_code_gen) free_reg(int reg) {
    if reg >= 0 {
        gen.reg_alloc.free_regs = append(gen.reg_alloc.free_regs, reg)
        gen.reg_alloc.reg_count = gen.reg_alloc.reg_count + 1
    }
}

func encode_mov_imm64_to_r64(int reg, int64 value) int8[] {
    code := int8[]()
    if reg >= reg_r8 {
        code = append(code, 0x49 as int8)
    } else {
        code = append(code, 0x48 as int8)
    }
    base := reg_rax
    if reg >= reg_r8 {
        base = reg - 8
    } else {
        base = reg
    }
    code = append(code, (0x_b8 + base) as int8)
    code = append(code, (value & 0x_ff) as int8)
    code = append(code, ((value >> 8) & 0x_ff) as int8)
    code = append(code, ((value >> 16) & 0x_ff) as int8)
    code = append(code, ((value >> 24) & 0x_ff) as int8)
    code = append(code, ((value >> 32) & 0x_ff) as int8)
    code = append(code, ((value >> 40) & 0x_ff) as int8)
    code = append(code, ((value >> 48) & 0x_ff) as int8)
    code = append(code, ((value >> 56) & 0x_ff) as int8)
    code
}

func encode_mov_r64_to_r64(int dst, int src) int8[] {
    code := int8[]()
    rex := 0x48 as int8
    if dst >= reg_r8 {
        rex = (rex | 0x04) as int8
    }
    if src >= reg_r8 {
        rex = (rex | 0x01) as int8
    }
    code = append(code, rex)
    code = append(code, 0x89 as int8)
    dst_reg := dst % 8
    src_reg := src % 8
    modrm := ((0x03 << 6) | (src_reg << 3) | dst_reg) as int8
    code = append(code, modrm)
    code
}

func encode_push_r64(int reg) int8[] {
    code := int8[]()
    if reg >= reg_r8 {
        code = append(code, 0x41 as int8)
    }
    base := reg % 8
    code = append(code, (0x50 + base) as int8)
    code
}

func encode_pop_r64(int reg) int8[] {
    code := int8[]()
    if reg >= reg_r8 {
        code = append(code, 0x41 as int8)
    }
    base := reg % 8
    code = append(code, (0x58 + base) as int8)
    code
}

func encode_add_imm32_to_r64(int reg, int32 value) int8[] {
    code := int8[]()
    rex := 0x48 as int8
    if reg >= reg_r8 {
        rex = (rex | 0x01) as int8
    }
    code = append(code, rex)
    if reg == reg_rsp || reg == reg_r8 + (reg_rsp - reg_rax) {
        code = append(code, 0x81 as int8)
        modrm := ((0x03 << 6) | (0x00 << 3) | (reg % 8)) as int8
        code = append(code, modrm)
    } else {
        code = append(code, 0x81 as int8)
        modrm := ((0x03 << 6) | (0x00 << 3) | (reg % 8)) as int8
        code = append(code, modrm)
    }
    code = append(code, (value & 0x_ff) as int8)
    code = append(code, ((value >> 8) & 0x_ff) as int8)
    code = append(code, ((value >> 16) & 0x_ff) as int8)
    code = append(code, ((value >> 24) & 0x_ff) as int8)
    code
}

func encode_sub_imm32_from_r64(int reg, int32 value) int8[] {
    code := int8[]()
    rex := 0x48 as int8
    if reg >= reg_r8 {
        rex = (rex | 0x01) as int8
    }
    code = append(code, rex)
    code = append(code, 0x81 as int8)
    modrm := ((0x03 << 6) | (0x05 << 3) | (reg % 8)) as int8
    code = append(code, modrm)
    code = append(code, (value & 0x_ff) as int8)
    code = append(code, ((value >> 8) & 0x_ff) as int8)
    code = append(code, ((value >> 16) & 0x_ff) as int8)
    code = append(code, ((value >> 24) & 0x_ff) as int8)
    code
}

func encode_ret() int8[] {
    code := int8[]()
    code = append(code, 0x_c3 as int8)
    code
}

func encode_call_rel32(int32 rel_offset) int8[] {
    code := int8[]()
    code = append(code, 0x_e8 as int8)
    code = append(code, (rel_offset & 0x_ff) as int8)
    code = append(code, ((rel_offset >> 8) & 0x_ff) as int8)
    code = append(code, ((rel_offset >> 16) & 0x_ff) as int8)
    code = append(code, ((rel_offset >> 24) & 0x_ff) as int8)
    code
}

func encode_jmp_rel32(int32 rel_offset) int8[] {
    code := int8[]()
    code = append(code, 0x_e9 as int8)
    code = append(code, (rel_offset & 0x_ff) as int8)
    code = append(code, ((rel_offset >> 8) & 0x_ff) as int8)
    code = append(code, ((rel_offset >> 16) & 0x_ff) as int8)
    code = append(code, ((rel_offset >> 24) & 0x_ff) as int8)
    code
}

func encode_cmp_r64_r64(int dst, int src) int8[] {
    code := int8[]()
    rex := 0x48 as int8
    if dst >= reg_r8 {
        rex = (rex | 0x04) as int8
    }
    if src >= reg_r8 {
        rex = (rex | 0x01) as int8
    }
    code = append(code, rex)
    code = append(code, 0x39 as int8)
    modrm := ((0x03 << 6) | (src % 8 << 3) | (dst % 8)) as int8
    code = append(code, modrm)
    code
}

func (gen* amd64_code_gen) gen_prologue(int64 stack_size) {
    code := encode_push_r64(reg_rbp)
    gen.mcg.stream.emit_raw_bytes(code)
    code = encode_mov_r64_to_r64(reg_rbp, reg_rsp)
    gen.mcg.stream.emit_raw_bytes(code)
    aligned_stack := ((stack_size + 15) / 16) * 16
    if aligned_stack > 0 {
        code = encode_sub_imm32_from_r64(reg_rsp, (aligned_stack & 0x_ffffffff) as int32)
        gen.mcg.stream.emit_raw_bytes(code)
    }
    gen.stack_depth = 0 as int64
    gen.max_stack_depth = aligned_stack
}

func (gen* amd64_code_gen) gen_epilogue() {
    if gen.max_stack_depth > 0 {
        code := encode_add_imm32_to_r64(reg_rsp, (gen.max_stack_depth & 0x_ffffffff) as int32)
        gen.mcg.stream.emit_raw_bytes(code)
    }
    code := encode_pop_r64(reg_rbp)
    gen.mcg.stream.emit_raw_bytes(code)
    code = encode_ret()
    gen.mcg.stream.emit_raw_bytes(code)
}

func (gen* amd64_code_gen) gen_func_from_ast(ast_func_decl* func) {
    gen.current_func_name = func.name
    gen.function_start_offset = gen.mcg.get_current_offset()
    stack_size := (64 as int64)
    gen.gen_prologue(stack_size)
    if func.body != nil {
        gen.gen_block_from_ast(func.body)
    }
    gen.gen_epilogue()
}

func (gen* amd64_code_gen) gen_block_from_ast(ast_block* block) {
    if block == nil {
        return
    }
    for i := 0; i < len(block.statements); i = i + 1 {
        stmt := block.statements[i]
        gen.gen_stmt_from_ast(stmt)
    }
}

func (gen* amd64_code_gen) gen_stmt_from_ast(ast_stmt* stmt) {
    if stmt == nil {
        return
    }
    if stmt.kind == ast_return_stmt {
        gen.gen_return_stmt(stmt)
    } else if stmt.kind == ast_if_stmt {
        gen.gen_if_stmt(stmt)
    } else if stmt.kind == ast_for_stmt {
        gen.gen_for_stmt(stmt)
    } else if stmt.kind == ast_expr_stmt {
        if stmt.expression != nil {
            gen.gen_expr_from_ast(stmt.expression)
        }
    } else if stmt.kind == ast_var_decl {
        gen.gen_var_decl(stmt)
    }
}

func (gen* amd64_code_gen) gen_return_stmt(ast_stmt* stmt) {
    if stmt.expression != nil {
        result_reg := gen.gen_expr_from_ast(stmt.expression)
        if result_reg != reg_rax && result_reg >= 0 {
            code := encode_mov_r64_to_r64(reg_rax, result_reg)
            gen.mcg.stream.emit_raw_bytes(code)
            gen.free_reg(result_reg)
        }
    } else {
        code := encode_mov_imm64_to_r64(reg_rax, 0 as int64)
        gen.mcg.stream.emit_raw_bytes(code)
    }
    gen.gen_epilogue()
}

func (gen* amd64_code_gen) gen_if_stmt(ast_stmt* stmt) {
    gen.label_counter = gen.label_counter + 1
    else_label := gen.label_counter
    gen.label_counter = gen.label_counter + 1
    end_label := gen.label_counter
    cond_reg := gen.gen_expr_from_ast(stmt.condition)
    code := encode_cmp_r64_r64(cond_reg, cond_reg)
    gen.mcg.stream.emit_raw_bytes(code)
    code = encode_call_rel32(0)
    gen.mcg.stream.emit_raw_bytes(code)
    gen.free_reg(cond_reg)
    if stmt.then_branch != nil {
        gen.gen_block_from_ast(stmt.then_branch)
    }
    if stmt.else_branch != nil {
        code = encode_jmp_rel32(0)
        gen.mcg.stream.emit_raw_bytes(code)
        gen.gen_block_from_ast(stmt.else_branch)
    }
}

func (gen* amd64_code_gen) gen_for_stmt(ast_stmt* stmt) {
    gen.label_counter = gen.label_counter + 1
    loop_label := gen.label_counter
    gen.label_counter = gen.label_counter + 1
    end_label := gen.label_counter
    if stmt.init != nil {
        gen.gen_stmt_from_ast(stmt.init)
    }
    if stmt.body != nil {
        gen.gen_block_from_ast(stmt.body)
    }
    if stmt.post != nil {
        gen.gen_stmt_from_ast(stmt.post)
    }
    if stmt.condition != nil {
        cond_reg := gen.gen_expr_from_ast(stmt.condition)
        code := encode_cmp_r64_r64(cond_reg, cond_reg)
        gen.mcg.stream.emit_raw_bytes(code)
        code = encode_call_rel32(0)
        gen.mcg.stream.emit_raw_bytes(code)
        gen.free_reg(cond_reg)
    }
}

func (gen* amd64_code_gen) gen_expr_from_ast(ast_expr* expr) int {
    if expr == nil {
        return -1
    }
    if expr.kind == ast_integer_literal {
        reg := gen.alloc_reg()
        value := expr.int_value
        code := encode_mov_imm64_to_r64(reg, value)
        gen.mcg.stream.emit_raw_bytes(code)
        return reg
    } else if expr.kind == ast_binary_op {
        left_reg := gen.gen_expr_from_ast(expr.left)
        right_reg := gen.gen_expr_from_ast(expr.right)
        if expr.op == 0x2_b {
            code := encode_add_imm32_to_r64(left_reg, 0)
            gen.mcg.stream.emit_raw_bytes(code)
            gen.free_reg(right_reg)
            return left_reg
        }
        return left_reg
    } else if expr.kind == ast_func_call {
        return reg_rax
    }
    return -1
}

func (gen* amd64_code_gen) gen_var_decl(ast_stmt* stmt) {
    if stmt.name != "" {
        gen.stack_depth = gen.stack_depth + 8 as int64
        if gen.stack_depth > gen.max_stack_depth {
            gen.max_stack_depth = gen.stack_depth
        }
    }
}

func (gen* amd64_code_gen) gen_from_ast_program(ast_program* prog) string {
    if prog == nil {
        return "error: null program"
    }
    gen.symtab.add_symbol(
        "main",
        symbol_bind_global,
        symbol_type_func,
        gen.mcg.get_current_offset(),
        0 as int64,
        1
    )
    for i := 0; i < len(prog.functions); i = i + 1 {
        func := prog.functions[i]
        gen.gen_func_from_ast(func)
    }
    ""
}
