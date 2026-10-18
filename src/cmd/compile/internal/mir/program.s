package compile.internal.mir

import (
    "std"
    "std.prelude"
)

// Executable module boundary. IDs are local to a function, symbols to a package.
// Physical value layout and native calling convention belong to later lowering.
struct mir_program_parameter {
    int value_id
    string name
    string type_name
}

struct mir_program_instruction {
    string op
    int[] result_ids
    string[] result_types
    int[] operands
    int integer_value
    string symbol
}

struct mir_program_block {
    int id
    mir_program_instruction[] instructions
    string terminator
    int[] return_values
}

struct mir_program_function {
    string symbol
    mir_program_parameter[] params
    string[] result_types
    mir_program_block[] blocks
    bool external
}

struct mir_program_call {
    string caller
    string callee
    int block_id
    int instruction_index
}

struct mir_program {
    string package_name
    string entry_symbol
    mir_program_function[] functions
    mir_program_call[] calls
}

struct mir_program_result {
    mir_program program
    string error
}

func mir_program_function_index(mir_program_function[] functions, string symbol) int {
    i := 0
    for i < len(functions) {
        if functions[i].symbol == symbol { return i }
        i = i + 1
    }
    return -1
}

// Only values defined before the current instruction are available in P1's
// straight-line blocks. No expression is evaluated to construct the module.
func mir_program_value_type(mir_program_function function_data, int id, int limit) string {
    i := 0
    for i < len(function_data.params) {
        if function_data.params[i].value_id == id { return function_data.params[i].type_name }
        i = i + 1
    }
    if len(function_data.blocks) != 1 { return "" }
    i = 0
    for i < limit {
        ins := function_data.blocks[0].instructions[i]
        r := 0
        for r < len(ins.result_ids) {
            if ins.result_ids[r] == id { return ins.result_types[r] }
            r = r + 1
        }
        i = i + 1
    }
    return ""
}

func mir_program_instruction_error(mir_program_function function_data, mir_program_function[] functions, mir_program_instruction ins, int index) string {
    if len(ins.result_ids) != len(ins.result_types) { return "result type count in: " + function_data.symbol }
    r := 0
    for r < len(ins.result_ids) {
        if ins.result_ids[r] < 0 || ins.result_types[r] == "" { return "invalid value in: " + function_data.symbol }
        if mir_program_value_type(function_data, ins.result_ids[r], index) != "" { return "duplicate value in: " + function_data.symbol }
        previous := 0
        for previous < r {
            if ins.result_ids[previous] == ins.result_ids[r] { return "duplicate value in: " + function_data.symbol }
            previous = previous + 1
        }
        r = r + 1
    }
    a := 0
    for a < len(ins.operands) {
        if mir_program_value_type(function_data, ins.operands[a], index) == "" { return "undefined value in: " + function_data.symbol }
        a = a + 1
    }
    if ins.op == "call" {
        target := mir_program_function_index(functions, ins.symbol)
        if target < 0 { return "unknown callee: " + ins.symbol }
        callee := functions[target]
        if len(ins.operands) != len(callee.params) { return "call argument count: " + ins.symbol }
        if len(ins.result_types) != len(callee.result_types) { return "call result count: " + ins.symbol }
        a = 0
        for a < len(ins.operands) {
            if mir_program_value_type(function_data, ins.operands[a], index) != callee.params[a].type_name {
                return "call argument type: " + ins.symbol
            }
            a = a + 1
        }
        r = 0
        for r < len(ins.result_types) {
            if ins.result_types[r] != callee.result_types[r] { return "call result type: " + ins.symbol }
            r = r + 1
        }
        return ""
    }
    if len(ins.result_ids) != 1 { return "instruction result count: " + ins.op }
    if ins.op == "const_int" {
        if len(ins.operands) != 0 || ins.result_types[0] != "int" { return "invalid integer constant" }
        return ""
    }
    if ins.op == "copy" {
        if len(ins.operands) != 1 { return "copy operand count" }
        if ins.result_types[0] != mir_program_value_type(function_data, ins.operands[0], index) { return "copy type mismatch" }
        return ""
    }
    if ins.op == "add" || ins.op == "sub" || ins.op == "mul" || ins.op == "div" || ins.op == "mod" {
        if len(ins.operands) != 2 { return "binary operand count: " + ins.op }
        if ins.result_types[0] != "int" { return "binary result type: " + ins.op }
        if mir_program_value_type(function_data, ins.operands[0], index) != "int" || mir_program_value_type(function_data, ins.operands[1], index) != "int" {
            return "binary operand type: " + ins.op
        }
        return ""
    }
    return "unsupported instruction: " + ins.op
}

func mir_program_function_error(mir_program_function function_data, mir_program_function[] functions) string {
    if function_data.symbol == "" { return "empty function symbol" }
    p := 0
    for p < len(function_data.params) {
        if function_data.params[p].value_id < 0 || function_data.params[p].name == "" || function_data.params[p].type_name == "" { return "invalid parameter: " + function_data.symbol }
        previous := 0
        for previous < p {
            if function_data.params[previous].value_id == function_data.params[p].value_id { return "duplicate parameter value: " + function_data.symbol }
            if function_data.params[previous].name == function_data.params[p].name { return "duplicate parameter name: " + function_data.symbol }
            previous = previous + 1
        }
        p = p + 1
    }
    p = 0
    for p < len(function_data.result_types) {
        if function_data.result_types[p] == "" { return "empty result type: " + function_data.symbol }
        p = p + 1
    }
    if function_data.external {
        if len(function_data.blocks) != 0 { return "external function has body: " + function_data.symbol }
        return ""
    }
    // P2 adds CFG/dominance lowering; do not fabricate branches in P1.
    if len(function_data.blocks) != 1 { return "P1 requires one straight-line block: " + function_data.symbol }
    block := function_data.blocks[0]
    if block.id < 0 { return "invalid block: " + function_data.symbol }
    i := 0
    for i < len(block.instructions) {
        error := mir_program_instruction_error(function_data, functions, block.instructions[i], i)
        if error != "" { return error }
        i = i + 1
    }
    if block.terminator != "return" { return "unsupported terminator: " + block.terminator }
    if len(block.return_values) != len(function_data.result_types) { return "return count: " + function_data.symbol }
    i = 0
    for i < len(block.return_values) {
        actual := mir_program_value_type(function_data, block.return_values[i], len(block.instructions))
        if actual == "" { return "undefined return value: " + function_data.symbol }
        if actual != function_data.result_types[i] { return "return type: " + function_data.symbol }
        i = i + 1
    }
    return ""
}

func mir_program_append_call(mir_program_call[] calls, string caller, string callee, int block_id, int instruction_index) mir_program_call[] {
    calls.push(mir_program_call {
        caller: caller, callee: callee, block_id: block_id, instruction_index: instruction_index,
    })
    return calls
}

func lower_mir_program(string package_name, string entry_symbol, mir_program_function[] functions) mir_program_result {
    empty := mir_program {
        package_name: package_name, entry_symbol: entry_symbol,
        functions: mir_program_function[]{}, calls: mir_program_call[]{},
    }
    result := mir_program_result { program: empty, error: "" }
    i := 0
    for i < len(functions) {
        previous := 0
        for previous < i {
            if functions[previous].symbol == functions[i].symbol {
                result.error = "duplicate function: " + functions[i].symbol
                return result
            }
            previous = previous + 1
        }
        i = i + 1
    }
    entry := mir_program_function_index(functions, entry_symbol)
    if entry < 0 { result.error = "entry function not found: " + entry_symbol; return result }
    if functions[entry].external { result.error = "entry function has no body: " + entry_symbol; return result }
    calls := []mir_program_call{}
    i = 0
    for i < len(functions) {
        error := mir_program_function_error(functions[i], functions)
        if error != "" { result.error = error; return result }
        b := 0
        for b < len(functions[i].blocks) {
            n := 0
            for n < len(functions[i].blocks[b].instructions) {
                ins := functions[i].blocks[b].instructions[n]
                if ins.op == "call" {
                    calls = mir_program_append_call(calls, functions[i].symbol, ins.symbol, functions[i].blocks[b].id, n)
                }
                n = n + 1
            }
            b = b + 1
        }
        i = i + 1
    }
    result.program = mir_program {
        package_name: package_name, entry_symbol: entry_symbol, functions: functions, calls: calls,
    }
    return result
}
