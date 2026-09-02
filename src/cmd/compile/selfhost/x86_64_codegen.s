package cmd
use std.strings.split as split_string
use std.strings.contains as contains_string
use std.strings.trim as trim_string
use std.fmt.sprintf
use std.io.eprintln
struct x86_64_gen {
    asm_lines: string[]
    register_stack: string[]
    temp_allocations: map[string]string
    label_count: int
}

func new_x86_64_gen() x86_64_gen {
    return x86_64_gen{
        asm_lines: string[]{},
        register_stack: []{
            "%rax", "%rbx", "%rcx", "%rdx", "%rsi", "%rdi",
            "%r8", "%r9", "%r10", "%r11", "%r12", "%r13",
            "%r14", "%r15",
        }, temp_allocations map[string]string{}, label_count 0,
    }
}

func (x86_64_gen* gen) emit(string line) {
    gen.asm_lines = append(gen.asm_lines, "    " + line)
}

func (x86_64_gen* gen) emit_label(string label) {
    gen.asm_lines = append(gen.asm_lines, label + ":")
}

func (x86_64_gen* gen) allocate_register() string {
    if len(gen.register_stack) > 0 {
        reg := gen.register_stack[0]
        gen.register_stack = gen.register_stack[1:]
        return reg
    }
    return ""
}

func (x86_64_gen* gen) free_register(string reg) {
    gen.register_stack = append(gen.register_stack, reg)
}

func (x86_64_gen* gen) get_location(string variable) string {
    if loc, exists := gen.temp_allocations[variable]; exists {
        return loc
    }
    reg := gen.allocate_register()
    if reg != "" {
        gen.temp_allocations[variable] = reg
        return reg
    }
    stack_offset := (len(gen.temp_allocations) + 1) * 8
    stack_loc := sprintf("-%d(%%rbp)", stack_offset)
    gen.temp_allocations[variable] = stack_loc
    return stack_loc
}

func (x86_64_gen* gen) translate_instruction(instruction instr) error {
    switch instr.opcode {
        case "FUNC_BEGIN":
            gen.emit("push %rbp")
            gen.emit("mov %rsp, %rbp")
            gen.emit("sub $256, %rsp")
            return nil
        case "FUNC_END":
            gen.emit("add $256, %rsp")
            gen.emit("pop %rbp")
            gen.emit("ret")
            return nil
        case "MOV":
            src_loc := gen.get_location(instr.src1)
            dst_loc := gen.get_location(instr.dest)
            if instr.src1 == "0" || instr.src1 == "1" {
                gen.emit("mov $" + instr.src1 + ", " + dst_loc)
            } else if contains_string(instr.src1, "\"") {
                gen.emit("mov $" + instr.src1 + ", " + dst_loc)
            } else {
                gen.emit("mov " + src_loc + ", %rax")
                gen.emit("mov %rax, " + dst_loc)
            }
            return nil
        case "ADD":
            src1_loc := gen.get_location(instr.src1)
            src2_loc := gen.get_location(instr.src2)
            dst_loc := gen.get_location(instr.dest)
            gen.emit("mov " + src1_loc + ", %rax")
            gen.emit("add " + src2_loc + ", %rax")
            gen.emit("mov %rax, " + dst_loc)
            return nil
        case "CMP_EQ":
            src1_loc := gen.get_location(instr.src1)
            src2_loc := gen.get_location(instr.src2)
            dst_loc := gen.get_location(instr.dest)
            gen.emit("mov " + src1_loc + ", %rax")
            gen.emit("cmp " + src2_loc + ", %rax")
            gen.emit("sete %al")
            gen.emit("movzx %al, " + dst_loc)
            return nil
        case "CMP_NE":
            src1_loc := gen.get_location(instr.src1)
            src2_loc := gen.get_location(instr.src2)
            dst_loc := gen.get_location(instr.dest)
            gen.emit("mov " + src1_loc + ", %rax")
            gen.emit("cmp " + src2_loc + ", %rax")
            gen.emit("setne %al")
            gen.emit("movzx %al, " + dst_loc)
            return nil
        case "JUMP_IF_FALSE":
            cond_loc := gen.get_location(instr.src2)
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
            gen.emit("call " + instr.src1)
            dst_loc := gen.get_location(instr.dest)
            if dst_loc != "" {
                gen.emit("mov %rax, " + dst_loc)
            }
            return nil
        case "ARG":
            return nil
        case "RET":
            ret_loc := instr.src1
            if ret_loc != "" && ret_loc != "0" {
                loc := gen.get_location(ret_loc)
                gen.emit("mov " + loc + ", %rax")
            } else {
                gen.emit("xor %rax, %rax")
            }
            gen.emit("add $256, %rsp")
            gen.emit("pop %rbp")
            gen.emit("ret")
            return nil
        case "PARAM":
            return nil
        default:
            return error("unknown IR opcode: " + instr.opcode
    }
}

func generate_assembly_from_ir([]instruction instructions) (string, error) {
    gen := new_x86_64_gen()
    gen.asm_lines = append(gen.asm_lines, ".globl main")
    gen.asm_lines = append(gen.asm_lines, ".text")
    gen.asm_lines = append(gen.asm_lines, "")
    for _, instr in instructions {
        err := gen.translate_instruction(instr)
        if err != nil {
            return "", err
        }
    }
    result := ""
    for _, line in gen.asm_lines {
        result += line + "\n"
    }
    return result, nil
}

func format_immediate(string value) string {
    if contains_string(value, "\"") {
        return "$0x0"
    }
    if value == "" || value == "_" {
        return "$0"
    }
    return "$" + value
}
