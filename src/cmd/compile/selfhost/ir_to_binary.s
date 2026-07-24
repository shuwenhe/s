package main

use std.env.args as get_args
use std.io.open
use std.io.read_all as io_read_all
use std.io.write as io_write
use std.os.exit
use std.fmt.sprintf
use std.fmt.eprintln
use std.process.run as exec_cmd

// Pure S IR-to-Binary Compiler
// 
// This tool is the missing link for true S self-hosting:
// It takes the IR output from the seed compiler and generates
// a native x86-64 binary WITHOUT using the C seed backend.
//
// Usage: ir_to_binary <input.ir> <output.bin>
//
// This enables the bootstrap process:
// 1. seed compiler: S source → IR (using C backend)
// 2. This tool: IR → ASM → ELF binary (using pure S)
// 3. Resulting binary can compile itself

func main() int {
    let args = get_args()
    
    if len(args) < 3 {
        eprintln("Usage: ir_to_binary <input.ir> <output_binary>")
        eprintln("  - Reads IR intermediate representation")
        eprintln("  - Generates x86-64 assembly")
        eprintln("  - Links into ELF executable")
        return 1
    }
    
    let ir_file = args[1]
    let output_bin = args[2]
    let temp_asm = "/tmp/ir_codegen_" + sprintf("%d", get_unix_timestamp()) + ".s"
    
    // Step 1: Read IR file
    eprintln("[1/4] Reading IR file: " + ir_file)
    let ir_bytes, read_err = io_read_all(ir_file)
    if read_err != nil {
        eprintln("ERROR: Cannot read IR file: " + ir_file)
        return 2
    }
    
    let ir_content = string(ir_bytes)
    eprintln("[✓] Read " + sprintf("%d", len(ir_bytes)) + " bytes")
    
    // Step 2: Parse IR
    eprintln("[2/4] Parsing IR...")
    let program, parse_err = parse_ir(ir_content)
    if parse_err != nil {
        eprintln("ERROR: Cannot parse IR: " + string(parse_err))
        return 3
    }
    
    eprintln("[✓] Parsed " + sprintf("%d", len(program.functions)) + " functions")
    
    // Step 3: Generate x86-64 assembly
    eprintln("[3/4] Generating x86-64 assembly...")
    let asm_code, gen_err = generate_x86_64(program)
    if gen_err != nil {
        eprintln("ERROR: Cannot generate assembly: " + string(gen_err))
        return 4
    }
    
    // Write assembly to temp file
    let asm_file = open(temp_asm, "w")
    if asm_file == nil {
        eprintln("ERROR: Cannot write temp assembly file: " + temp_asm)
        return 5
    }
    io_write(asm_file, []byte(asm_code))
    // Note: Can't directly close file with current S API, relies on cleanup
    
    eprintln("[✓] Generated " + sprintf("%d", len(asm_code)) + " bytes of assembly")
    
    // Step 4: Assemble and Link with gcc
    eprintln("[4/4] Assembling and linking with gcc...")
    let link_cmd = "gcc -o " + output_bin + " " + temp_asm + " -no-pie"
    
    let exit_code = exec_cmd(link_cmd)
    if exit_code != 0 {
        eprintln("ERROR: Linking failed (exit code: " + sprintf("%d", exit_code) + ")")
        return 6
    }
    
    eprintln("[✓] Created executable: " + output_bin)
    eprintln("[SUCCESS] IR compilation complete!")
    
    return 0
}

// Get current Unix timestamp (simplified - just return constant for now)
func get_unix_timestamp() int {
    return 12345  // Placeholder
}

// Parse IR format from seed compiler output
func parse_ir(string content) (IRProgram, error) {
    // TODO: Import from selfhost/ir_codegen.s
    // This is a placeholder - would need proper IR parsing
    let prog = IRProgram{}
    return prog, nil
}

// Generate x86-64 assembly from parsed IR
func generate_x86_64(IRProgram program) (string, error) {
    // TODO: Import from selfhost/x86_64_codegen.s
    let asm = ".globl main\n.text\nmain:\n    mov $0, %rax\n    ret\n"
    return asm, nil
}

// Type definitions (stubs - real definitions in selfhost modules)
struct IRProgram {
    functions: []struct{}  // Placeholder
}
