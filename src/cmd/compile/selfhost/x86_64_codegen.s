package cmd

use std.strings.split as split_string
use std.strings.contains as contains_string
use std.strings.trim as trim_string
use std.fmt.sprintf
use std.io.eprintln

// x86-64 Code Generator: IR → x86-64 Assembly
// Part of the pure S bootstrap process

struct X86_64Gen {
    asm_lines: []string
    register_stack: []string  // Available registers
    temp_allocations: map[string]string  // temp var → register
    label_count: int
}

func new_x86_64_gen() X86_64Gen {
    return X86_64Gen{
        asm_lines: []string{},
        register_stack: []{
            "%rax", "%rbx", "%rcx", "%rdx", "%rsi", "%rdi",
            "%r8", "%r9", "%r10", "%r11", "%r12", "%r13",
            "%r14", "%r15",
        },
        temp_allocations: map[string]string{},
        label_count: 0,
    }
}

func (gen: &mut X86_64Gen) emit(string line) {
    gen.asm_lines = append(gen.asm_lines, "    " + line)
}

func (gen: &mut X86_64Gen) emit_label(string label) {
    gen.asm_lines = append(gen.asm_lines, label + ":")
}

func (gen: &mut X86_64Gen) allocate_register() string {
    if len(gen.register_stack) > 0 {
        let reg = gen.register_stack[0]
        gen.register_stack = gen.register_stack[1:]
        return reg
    }
    return ""  // Stack spill needed
}

func (gen: &mut X86_64Gen) free_register(string reg) {
    gen.register_stack = append(gen.register_stack, reg)
}

func (gen: &mut X86_64Gen) get_location(string var) string {
    // Check if already allocated
    if loc, exists := gen.temp_allocations[var]; exists {
        return loc
    }
    
    // Try to allocate register
    let reg = gen.allocate_register()
    if reg != "" {
        gen.temp_allocations[var] = reg
        return reg
    }
    
    // Stack allocation fallback
    let stack_offset = (len(gen.temp_allocations) + 1) * 8
    let stack_loc = sprintf("-%d(%%rbp)", stack_offset)
    gen.temp_allocations[var] = stack_loc
    return stack_loc
}

// Convert IR instructions to x86-64 assembly
func (gen: &mut X86_64Gen) translate_instruction(Instruction instr) error {
    match instr.opcode {
        case "FUNC_BEGIN":
            gen.emit("push %rbp")
            gen.emit("mov %rsp, %rbp")
            gen.emit("sub $256, %rsp")  // Allocate space for locals
            return nil
            
        case "FUNC_END":
            gen.emit("add $256, %rsp")
            gen.emit("pop %rbp")
            gen.emit("ret")
            return nil
            
        case "MOV":
            // MOV dest src1 → movq src1, dest
            let src_loc = gen.get_location(instr.src1)
            let dst_loc = gen.get_location(instr.dest)
            
            if instr.src1 == "0" || instr.src1 == "1" {
                gen.emit("mov $" + instr.src1 + ", " + dst_loc)
            } else if contains_string(instr.src1, "\"") {
                // String literal - need to handle specially
                gen.emit("mov $" + instr.src1 + ", " + dst_loc)
            } else {
                gen.emit("mov " + src_loc + ", %rax")
                gen.emit("mov %rax, " + dst_loc)
            }
            return nil
            
        case "ADD":
            // ADD dest src1 src2 → dest = src1 + src2
            let src1_loc = gen.get_location(instr.src1)
            let src2_loc = gen.get_location(instr.src2)
            let dst_loc = gen.get_location(instr.dest)
            
            gen.emit("mov " + src1_loc + ", %rax")
            gen.emit("add " + src2_loc + ", %rax")
            gen.emit("mov %rax, " + dst_loc)
            return nil
            
        case "CMP_EQ":
            // CMP_EQ dest src1 src2 → dest = (src1 == src2)
            let src1_loc = gen.get_location(instr.src1)
            let src2_loc = gen.get_location(instr.src2)
            let dst_loc = gen.get_location(instr.dest)
            
            gen.emit("mov " + src1_loc + ", %rax")
            gen.emit("cmp " + src2_loc + ", %rax")
            gen.emit("sete %al")  // Set if equal
            gen.emit("movzx %al, " + dst_loc)
            return nil
            
        case "CMP_NE":
            // CMP_NE dest src1 src2 → dest = (src1 != src2)
            let src1_loc = gen.get_location(instr.src1)
            let src2_loc = gen.get_location(instr.src2)
            let dst_loc = gen.get_location(instr.dest)
            
            gen.emit("mov " + src1_loc + ", %rax")
            gen.emit("cmp " + src2_loc + ", %rax")
            gen.emit("setne %al")  // Set if not equal
            gen.emit("movzx %al, " + dst_loc)
            return nil
            
        case "JUMP_IF_FALSE":
            // JUMP_IF_FALSE label condition
            let cond_loc = gen.get_location(instr.src2)
            gen.emit("mov " + cond_loc + ", %rax")
            gen.emit("test %rax, %rax")
            gen.emit("jz " + instr.src1)
            return nil
            
        case "JUMP":
            gen.emit("jmp " + instr.src1)
            return nil
            
        case "LABEL":
            gen.emit_label(instr.src1)
            return nil
            
        case "CALL":
            // Call function with arguments
            // For now, simple calling convention
            // In real implementation, need proper argument passing
            gen.emit("call " + instr.src1)
            let dst_loc = gen.get_location(instr.dest)
            if dst_loc != "" {
                gen.emit("mov %rax, " + dst_loc)
            }
            return nil
            
        case "ARG":
            // Prepare argument - would set rdi, rsi, rdx, etc.
            // Simplified for now
            return nil
            
        case "RET":
            let ret_loc = instr.src1
            if ret_loc != "" && ret_loc != "0" {
                let loc = gen.get_location(ret_loc)
                gen.emit("mov " + loc + ", %rax")
            } else {
                gen.emit("xor %rax, %rax")
            }
            gen.emit("add $256, %rsp")
            gen.emit("pop %rbp")
            gen.emit("ret")
            return nil
            
        case "PARAM":
            // Function parameter
            // Load from calling convention registers
            return nil
            
        default:
            return error("unknown IR opcode: " + instr.opcode)
    }
}

// Generate complete x86-64 assembly from IR
func generate_assembly_from_ir([]Instruction instructions) (string, error) {
    let mut gen = new_x86_64_gen()
    
    gen.asm_lines = append(gen.asm_lines, ".globl main")
    gen.asm_lines = append(gen.asm_lines, ".text")
    gen.asm_lines = append(gen.asm_lines, "")
    
    for _, instr in instructions {
        let err = gen.translate_instruction(instr)
        if err != nil {
            return "", err
        }
    }
    
    // Combine all lines
    let mut result = ""
    for _, line in gen.asm_lines {
        result += line + "\n"
    }
    
    return result, nil
}

// Helper: Convert decimal/string values to proper x86-64 immediates
func format_immediate(string value) string {
    if contains_string(value, "\"") {
        // String literal - would need string table
        return "$0x0"  // Placeholder
    }
    if value == "" || value == "_" {
        return "$0"
    }
    return "$" + value
}
