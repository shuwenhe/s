package seed.codegen

use std.vec.vec
use std.string.string

func instruction_select_mov(ctx: &mut codegen_context, ra: &mut register_allocator, op1: string, result: string) {
    dst_reg, _ := ra.allocate(result)
    
    if is_numeric(op1) {
        value := parse_int(op1)
        ctx.emit_line("    mov $" + value as string + ", %" + dst_reg)
    } else {
        src_reg, _ := ra.allocate(op1)
        ctx.emit_line("    mov %" + src_reg + ", %" + dst_reg)
    }
}

func instruction_select_add(ctx: &mut codegen_context, ra: &mut register_allocator, op1: string, op2: string, result: string) {
    dst_reg, _ := ra.allocate(result)
    src_reg, _ := ra.allocate(op1)
    
    ctx.emit_line("    mov %" + src_reg + ", %" + dst_reg)
    
    if is_numeric(op2) {
        value := parse_int(op2)
        ctx.emit_line("    add $" + value as string + ", %" + dst_reg)
    } else {
        other_reg, _ := ra.allocate(op2)
        ctx.emit_line("    add %" + other_reg + ", %" + dst_reg)
    }
}

func instruction_select_sub(ctx: &mut codegen_context, ra: &mut register_allocator, op1: string, op2: string, result: string) {
    dst_reg, _ := ra.allocate(result)
    src_reg, _ := ra.allocate(op1)
    
    ctx.emit_line("    mov %" + src_reg + ", %" + dst_reg)
    
    if is_numeric(op2) {
        value := parse_int(op2)
        ctx.emit_line("    sub $" + value as string + ", %" + dst_reg)
    } else {
        other_reg, _ := ra.allocate(op2)
        ctx.emit_line("    sub %" + other_reg + ", %" + dst_reg)
    }
}

func instruction_select_mul(ctx: &mut codegen_context, ra: &mut register_allocator, op1: string, op2: string, result: string) {
    dst_reg, _ := ra.allocate(result)
    
    ctx.emit_line("    mov %" + dst_reg + ", %rax")
    
    if is_numeric(op2) {
        value := parse_int(op2)
        ctx.emit_line("    mov $" + value as string + ", %rcx")
        ctx.emit_line("    imul %rcx, %rax")
    } else {
        other_reg, _ := ra.allocate(op2)
        ctx.emit_line("    imul %" + other_reg + ", %rax")
    }
    
    ctx.emit_line("    mov %rax, %" + dst_reg)
}

func instruction_select_cmp(ctx: &mut codegen_context, ra: &mut register_allocator, op1: string, op2: string) {
    if is_numeric(op1) {
        ctx.emit_line("    mov $" + op1 + ", %rax")
        src_reg := "rax"
    } else {
        src_reg, _ := ra.allocate(op1)
    }
    
    if is_numeric(op2) {
        ctx.emit_line("    cmp $" + op2 + ", %" + src_reg)
    } else {
        dst_reg, _ := ra.allocate(op2)
        ctx.emit_line("    cmp %" + dst_reg + ", %" + src_reg)
    }
}

func instruction_select_call(ctx: &mut codegen_context, ra: &mut register_allocator, fn_name: string, args: string[]) {
    param_regs := vec[]()
    param_regs.push("rdi")
    param_regs.push("rsi")
    param_regs.push("rdx")
    param_regs.push("rcx")
    param_regs.push("r8")
    param_regs.push("r9")
    
    for i < args.len() {
        if i < param_regs.len() {
            param_reg := param_regs[i]
            if is_numeric(args[i]) {
                ctx.emit_line("    mov $" + args[i] + ", %" + param_reg)
            } else {
                src_reg, _ := ra.allocate(args[i])
                ctx.emit_line("    mov %" + src_reg + ", %" + param_reg)
            }
        }
    }
    
    ctx.emit_line("    call " + fn_name)
}

func instruction_select_ret(ctx: &mut codegen_context, ra: &mut register_allocator, value: string) {
    if value != "" {
        if is_numeric(value) {
            ctx.emit_line("    mov $" + value + ", %rax")
        } else {
            src_reg := ra.get_register(value)
            if src_reg != "" {
                ctx.emit_line("    mov %" + src_reg + ", %rax")
            }
        }
    }
    
    ctx.emit_line("    leave")
    ctx.emit_line("    ret")
}

func is_numeric(s: string) bool {
    if s.len() == 0 {
        return false
    }
    
    for i < s.len() {
        c := s[i]
        if c < '0' || c > '9' {
            return false
        }
    }
    true
}

func parse_int(s: string) int {
    result := 0
    for i < s.len() {
        c := s[i]
        if c >= '0' && c <= '9' {
            result = result * 10 + (c as int - '0' as int)
        }
    }
    result
}
