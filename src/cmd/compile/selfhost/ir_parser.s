package ir
use std.strings.split as split_string
use std.strings.trim as trim_string
use std.strings.contains as contains_string
use std.fmt.sprintf

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

func parse_ir(string content) (IRModule, error) {
    lines := split_string(content, "\n")
    module := IRModule{
        target: "x86_64",
        version: "1",
        functions: []IRFunction{},
    }
    if len(lines) == 0 {
        return module, error("empty IR")
    }
    header := trim_string(lines[0])
    if header != "SSEED-TARGET-V1" {
        return module, error("invalid IR header: " + header)
    }
    i := 1
    current_func: *IRFunction = nil
    for i < len(lines) {
        line := trim_string(lines[i])
        if line == "" {
            i += 1
            continue
        }
        parts := split_string(line, "|")
        if len(parts) == 0 {
            i += 1
            continue
        }
        opcode := parts[0]
        match opcode {
            case "FUNC_BEGIN":
                if len(parts) >= 2 {
                    func := IRFunction{
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
                    instr := IRInstruction{
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

func get_ir_stats(IRModule module) map[string]int {
    stats := map[string]int{}
    stats["total_functions"] = len(module.functions)
    total_instrs := 0
    opcode_counts := map[string]int{}
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

func verify_ir(IRModule module) error {
    if len(module.functions) == 0 {
        return error("no functions in IR")
    }
    for _, func in module.functions {
        if func.name == "" {
            return error("function with empty name")
        }
    }
    return nil
}

func instruction_to_string(IRInstruction instr) string {
    s := instr.opcode
    s += "|" + instr.dest
    s += "|" + instr.src1
    s += "|" + instr.src2
    return s
}
