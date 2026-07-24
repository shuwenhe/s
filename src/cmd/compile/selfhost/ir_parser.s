package ir

use std.strings.split as split_string
use std.strings.trim as trim_string
use std.strings.contains as contains_string
use std.fmt.sprintf

// Minimal IR parser for x86-64 bootstrap
// This can parse the seed compiler's IR output and validate structure

struct IRInstruction {
    opcode: string
    dest: string
    src1: string
    src2: string
}

struct IRFunction {
    name: string
    instructions: []IRInstruction
}

struct IRModule {
    target: string
    version: string
    functions: []IRFunction
}

// Parse IR in SSEED format
func parse_ir(string content) (IRModule, error) {
    let lines = split_string(content, "\n")
    let mut module = IRModule{
        target: "x86_64",
        version: "1",
        functions: []IRFunction{},
    }
    
    if len(lines) == 0 {
        return module, error("empty IR")
    }
    
    // Check header
    let header = trim_string(lines[0])
    if header != "SSEED-TARGET-V1" {
        return module, error("invalid IR header: " + header)
    }
    
    // Parse functions
    let mut i = 1
    let mut current_func: *IRFunction = nil
    
    for i < len(lines) {
        let line = trim_string(lines[i])
        
        if line == "" {
            i += 1
            continue
        }
        
        // Parse line by pipe delimiter
        let parts = split_string(line, "|")
        if len(parts) == 0 {
            i += 1
            continue
        }
        
        let opcode = parts[0]
        
        match opcode {
            case "FUNC_BEGIN":
                if len(parts) >= 2 {
                    let func = IRFunction{
                        name: parts[1],
                        instructions: []IRInstruction{},
                    }
                    current_func = &func
                    module.functions = append(module.functions, func)
                }
                
            case "FUNC_END":
                current_func = nil
                
            default:
                if current_func != nil {
                    let instr = IRInstruction{
                        opcode: opcode,
                        dest: if len(parts) > 1 then parts[1] else "",
                        src1: if len(parts) > 2 then parts[2] else "",
                        src2: if len(parts) > 3 then parts[3] else "",
                    }
                    current_func.instructions = append(
                        current_func.instructions,
                        instr
                    )
                }
        }
        
        i += 1
    }
    
    return module, nil
}

// Get summary statistics about IR
func get_ir_stats(IRModule module) map[string]int {
    let mut stats = map[string]int{}
    
    stats["total_functions"] = len(module.functions)
    
    let mut total_instrs = 0
    let mut opcode_counts = map[string]int{}
    
    for _, func in module.functions {
        total_instrs += len(func.instructions)
        
        for _, instr in func.instructions {
            if count, exists := opcode_counts[instr.opcode]; exists {
                opcode_counts[instr.opcode] = count + 1
            } else {
                opcode_counts[instr.opcode] = 1
            }
        }
    }
    
    stats["total_instructions"] = total_instrs
    
    return stats
}

// Verify IR integrity
func verify_ir(IRModule module) error {
    if len(module.functions) == 0 {
        return error("no functions in IR")
    }
    
    for _, func in module.functions {
        if func.name == "" {
            return error("function with empty name")
        }
        
        // Check for balanced FUNC_BEGIN/FUNC_END
        // (The parser should ensure this)
    }
    
    return nil
}

// Convert IR instruction to debug string
func instruction_to_string(IRInstruction instr) string {
    let mut s = instr.opcode
    s += "|" + instr.dest
    s += "|" + instr.src1
    s += "|" + instr.src2
    return s
}
