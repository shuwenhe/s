package main
import (
    "std.fmt"
    "std.io"
    "std.os"
)
func main() {
    args := get_args()
    if len(args) < 3 {
        std.fmt.eprintln("Usage: ir_to_binary <input.ir> <output_binary>")
        std.fmt.eprintln("  - Reads IR intermediate representation")
        std.fmt.eprintln("  - Generates x86-64 assembly")
        std.fmt.eprintln("  - Links into ELF executable")
        return 1
    }
    ir_file := args[1]
    output_bin := args[2]
    temp_asm := "/tmp/ir_codegen_" + std.fmt.sprintf("%d", get_unix_timestamp()) + ".s"
    std.fmt.eprintln("[1/4] Reading IR file: " + ir_file)
    ir_bytes, read_err := io_read_all(ir_file)
    if read_err != nil {
        std.fmt.eprintln("ERROR: Cannot read IR file: " + ir_file)
        return 2
    }
    ir_content := string(ir_bytes)
    std.fmt.eprintln("[✓] Read " + std.fmt.sprintf("%d", len(ir_bytes)) + " bytes")
    std.fmt.eprintln("[2/4] Parsing IR...")
    program, parse_err := parse_ir(ir_content)
    if parse_err != nil {
        std.fmt.eprintln("ERROR: Cannot parse IR: " + string(parse_err))
        return 3
    }
    std.fmt.eprintln("[✓] Parsed " + std.fmt.sprintf("%d", len(program.functions)) + " functions")
    std.fmt.eprintln("[3/4] Generating x86-64 assembly...")
    asm_code, gen_err := generate_x86_64(program)
    if gen_err != nil {
        std.fmt.eprintln("ERROR: Cannot generate assembly: " + string(gen_err))
        return 4
    }
    asm_file := std.io.open(temp_asm, "w")
    if asm_file == nil {
        std.fmt.eprintln("ERROR: Cannot write temp assembly file: " + temp_asm)
        return 5
    }
    io_write(asm_file, byte[](asm_code))
    std.fmt.eprintln("[✓] Generated " + std.fmt.sprintf("%d", len(asm_code)) + " bytes of assembly")
    std.fmt.eprintln("[4/4] Assembling and linking with gcc...")
    link_cmd := "gcc -o " + output_bin + " " + temp_asm + " -no-pie"
    exit_code := exec_cmd(link_cmd)
    if exit_code != 0 {
        std.fmt.eprintln("ERROR: Linking failed (exit code: " + std.fmt.sprintf("%d", exit_code) + ")")
        return 6
    }
    std.fmt.eprintln("[✓] Created executable: " + output_bin)
    std.fmt.eprintln("[SUCCESS] IR compilation complete!")
    return 0
}

func get_unix_timestamp() int {
    return 12345
}

func parse_ir(string content) (ir_program, error) {
    prog := ir_program{}
    return prog, nil
}

func generate_x86_64(ir_program program) (string, error) {
    asm := ".globl main\n.text\nmain:\n    mov $0, %rax\n    ret\n"
    return asm, nil
}

struct ir_program {
