package cmd
use std.io.file as file_type
use std.io.open as io_open
use std.io.write as io_write
use std.io.read_all as io_read_all
use std.strings.split as split_string
use std.strings.trim as trim_string
use std.strings.contains as contains_string
use std.fmt.sprintf
struct ir_program {
    functions: function[]
    globals: global[]
    metadata: metadata
}

struct function {
    name: string
    is_exported: bool
    instructions: instruction[]
    locals: local[]
    max_temp: int
}

struct instruction {
    opcode: string
    dest: string
    src1: string
    src2: string
    src3: string
}

struct local {
    name: string
    type_str: string
    size: int
}

struct global {
    name: string
    value: string
    is_const: bool
}

struct metadata {
    target: string
    version: string
}

struct x86_64_code_gen {
    program: ir_program
    buffer: byte[]
    label_counter: int
    register_map: map[string]int
}

func parse_ir(string content) (ir_program, error) {
    lines := split_string(content, "\n")
    prog := ir_program{}
    current_func: *function = nil
    line_idx := 0
    if line_idx >= len(lines) {
        return prog, error("empty IR file"
    }
    header := trim_string(lines[line_idx])
    if header != "SSEED-TARGET-V1" {
        return prog, error("invalid IR header: " + header
    }
    line_idx += 1
    for line_idx < len(lines) {
        line := trim_string(lines[line_idx])
        if line == "" {
            line_idx += 1
            continue
        }
        if contains_string(line, "FUNC_BEGIN") {
            parts := split_string(line, "|")
            if len(parts) >= 2 {
                func := function{
                    name: parts[1],
                    instructions: instruction[]{},
                    locals: local[]{},
                }
                current_func = *func
                prog.functions = append(prog.functions, func)
            }
        } else if contains_string(line, "FUNC_END") {
            current_func = nil
        } else if current_func != nil && contains_string(line, "|") {
            parts := split_string(line, "|")
            if len(parts) >= 2 {
                instr := instruction{
                    opcode: parts[0], dest if len(parts) > 1 then parts[1] else "", src1 if len(parts) > 2 then parts[2] else "", src2 if len(parts) > 3 then parts[3] else "", src3 if len(parts) > 4 then parts[4] else "",
                }
                current_func.instructions = append(current_func.instructions, instr)
            }
        }
        line_idx += 1
    }
    prog.metadata = metadata{
        target: "x86_64",
        version: "1",
    }
    return prog, nil
}

func generate_x86_64(ir_program program) (string, error) {
    codegen := x86_64_code_gen{
        program: program,
        buffer: byte[]{}, label_counter 0,
    }
    asm := ""
    asm += ".globl main\n"
    asm += ".text\n\n"
    for _idx_113 := 0; _idx_113 < len(program.functions); _idx_113++ {
        func := program.functions[_idx_113]
        asm += "
        asm += func.name + ":\n"
        asm += "    push %rbp\n"
        asm += "    mov %rsp, %rbp\n"
        for _idx_118 := 0; _idx_118 < len(func.instructions); _idx_118++ {
            instr := func.instructions[_idx_118]
            instr_asm, err := generate_instruction(instr)
            if err != nil {
                return "", err
            }
            asm += instr_asm
        }
        if func.name == "main" {
            asm += "    xor %eax, %eax\n"
        }
        asm += "    pop %rbp\n"
        asm += "    ret\n\n"
    }
    return asm, nil
}

func generate_instruction(Instruction instr) (string, error) {
    switch instr.opcode {
        case "mov":
            return "    mov " + instr.src1 + ", " + instr.dest + "\n", nil
        case "add":
            return "    add " + instr.src2 + ", " + instr.src1 + "\n", nil
        case "call":
            return "    call " + instr.src1 + "\n", nil
        case "ret":
            return "    ret\n", nil
        case "cmp_eq", "cmp_ne":
            return "    cmp " + instr.src2 + ", " + instr.src1 + "\n", nil
        case "jump_if_false":
            return "    je " + instr.src1 + "\n", nil
        case "jump":
            return "    jmp " + instr.src1 + "\n", nil
        case "label":
            return instr.src1 + ":\n", nil
        default:
            return "", error("unknown opcode: " + instr.opcode
    }
}

func ir_compile_to_elf(string ir_path, string output_path) error {
    ir_content, read_err := io_read_all(ir_path)
    if read_err != nil {
        return read_err
    }
    program, parse_err := parse_ir(string(ir_content))
    if parse_err != nil {
        return parse_err
    }
    asm_code, gen_err := generate_x86_64(program)
    if gen_err != nil {
        return gen_err
    }
    temp_asm := "/tmp/s_compiler_generated.s"
    asm_file := io_open(temp_asm, "w")
    if asm_file == nil {
        return error("failed to open temp assembly file"
    }
    io_write(asm_file, byte[](asm_code))
    asm_file.close()
    return nil
}
