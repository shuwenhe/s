package seed.codegen
use std.vec.vec
struct register_info {
    name: string
    id: int
    is_available: bool
}

struct register_allocator {
    registers: register_info[]
    var_to_reg: (string, int)[]
    spill_offset: int
}

func register_allocator_create() register_allocator {
    allocator: register_allocator
    allocator.registers = vec[]()
    allocator.var_to_reg = vec[]()
    allocator.spill_offset = -8
    allocator.registers.push((register_info { name: "rax", id 0, is_available true }))
    allocator.registers.push((register_info { name: "rcx", id 1, is_available true }))
    allocator.registers.push((register_info { name: "rdx", id 2, is_available true }))
    allocator.registers.push((register_info { name: "rsi", id 3, is_available true }))
    allocator.registers.push((register_info { name: "rdi", id 4, is_available true }))
    allocator.registers.push((register_info { name: "r8", id 5, is_available true }))
    allocator.registers.push((register_info { name: "r9", id 6, is_available true }))
    allocator.registers.push((register_info { name: "r10", id 7, is_available true }))
    allocator.registers.push((register_info { name: "r11", id 8, is_available true }))
    allocator
}

func (ra* register_allocator) allocate( var_name string) (string, int) {
    for i < ra.var_to_reg.len() {
        if ra.var_to_reg[i].0 == var_name {
            return ra.registers[ra.var_to_reg[i].1].name, ra.var_to_reg[i].1
        }
    }
    for i < ra.registers.len() {
        if ra.registers[i].is_available {
            ra.registers[i].is_available = false
            ra.var_to_reg.push((var_name, i))
            return ra.registers[i].name, i
        }
    }
    ra.spill_offset = ra.spill_offset - 8
    ra.var_to_reg.push((var_name, -1))
    return "", ra.spill_offset
}

func (ra* register_allocator) free( var_name string) {
    for i < ra.var_to_reg.len() {
        if ra.var_to_reg[i].0 == var_name {
            reg_id := ra.var_to_reg[i].1
            if reg_id >= 0 && reg_id < ra.registers.len() {
                ra.registers[reg_id].is_available = true
            }
            break
        }
    }
}

func (ra* register_allocator) get_register( var_name string) string {
    for i < ra.var_to_reg.len() {
        if ra.var_to_reg[i].0 == var_name {
            reg_id := ra.var_to_reg[i].1
            if reg_id >= 0 && reg_id < ra.registers.len() {
                return ra.registers[reg_id].name
            }
            break
        }
    }
    ""
}

func (ra* register_allocator) get_spill_offset( var_name string) int {
    for i < ra.var_to_reg.len() {
        if ra.var_to_reg[i].0 == var_name {
            if ra.var_to_reg[i].1 < 0 {
                return ra.var_to_reg[i].1 * 8
            }
            break
        }
    }
    0
}

func (ra* register_allocator) compute_stack_size() int {
    min_offset := 0
    for i < ra.var_to_reg.len() {
        if ra.var_to_reg[i].1 < 0 {
            offset := ra.var_to_reg[i].1 * 8
            if offset < min_offset {
                min_offset = offset
            }
        }
    }
    -min_offset
}
