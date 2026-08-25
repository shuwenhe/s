package cmd
use std.io.File as file_type
use std.io.open as io_open
use std.io.write as io_write
use std.io.read_all as io_read_all
use std.strings.split as split_string
use std.strings.trim as trim_string
use std.strings.contains as contains_string
use std.fmt.sprintf

struct IRProgram {
    functions: []Function
    globals: []Global
    metadata: Metadata
}

struct Function {
    name: string
    is_exported: bool
    instructions: []Instruction
    locals: []Local
    max_temp: int
}

struct Instruction {
    opcode: string
    dest: string
    src1: string
    src2: string
    src3: string
}

struct Local {
    name: string
    type_str: string
    size: int
}

struct Global {
    name: string
    value: string
    is_const: bool
}

struct Metadata {
    target: string
    version: string
}

struct X86_64CodeGen {
    program: IRProgram
    buffer: []byte
    label_counter: int
    register_map: map[string]int
}

func parse_ir(string content) (IRProgram, error) {
    lines := split_string(content, "\n")
    prog := IRProgram{}
    current_func: *Function = nil
    line_idx := 0
    if line_idx >= len(lines) {
        return prog, error("empty IR file")
    }
    header := trim_string(lines[line_idx])
    if header != "SSEED-TARGET-V1" {
        return prog, error("invalid IR header: " + header)
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
                func := Function{
                    name: parts[1],
                    instructions: []Instruction{},
                    locals: []Local{},
                }
                current_func = &func
                prog.functions = append(prog.functions, func)
            }
        } else if contains_string(line, "FUNC_END") {
            current_func = nil
        } else if current_func != nil && contains_string(line, "|") {
            parts := split_string(line, "|")
            if len(parts) >= 2 {
                instr := Instruction{
                    opcode: parts[0],
                    dest: if len(parts) > 1 then parts[1] else "",
                    src1: if len(parts) > 2 then parts[2] else "",
                    src2: if len(parts) > 3 then parts[3] else "",
                    src3: if len(parts) > 4 then parts[4] else "",
                }
                current_func.instructions = append(current_func.instructions, instr)
            }
        }
        line_idx += 1
    }
    prog.metadata = Metadata{
        target: "x86_64",
        version: "1",
    }
    return prog, nil
}

func generate_x86_64(IRProgram program) (string, error) {
    codegen := X86_64CodeGen{
        program: program,
        buffer: []byte{},
        label_counter: 0,
    }
    asm := ""
    asm += ".globl main\n"
    asm += ".text\n\n"
    for _, func in program.functions {
        asm += "
        asm += func.name + ":\n"
        asm += "    push %rbp\n"
        asm += "    mov %rsp, %rbp\n"
        for _, instr in func.instructions {
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
    match instr.opcode {
        case "MOV":
            return "    mov " + instr.src1 + ", " + instr.dest + "\n", nil
        case "ADD":
            return "    add " + instr.src2 + ", " + instr.src1 + "\n", nil
        case "CALL":
            return "    call " + instr.src1 + "\n", nil
        case "RET":
            return "    ret\n", nil
        case "CMP_EQ", "CMP_NE":
            return "    cmp " + instr.src2 + ", " + instr.src1 + "\n", nil
        case "JUMP_IF_FALSE":
            return "    je " + instr.src1 + "\n", nil
        case "JUMP":
            return "    jmp " + instr.src1 + "\n", nil
        case "LABEL":
            return instr.src1 + ":\n", nil
        default:
            return "", error("unknown opcode: " + instr.opcode)
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
        return error("failed to open temp assembly file")
    }
    io_write(asm_file, []byte(asm_code))
    asm_file.close()
    return nil
}
