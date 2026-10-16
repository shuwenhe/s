package compile.internal.codegen

import (
    "compile.internal.mir"
)

// C is an explicit target for the existing executable module MIR. This module
// accepts no source text, AST, precomputed writes or interpreter results.
// The bootstrap host may execute this S implementation; emitted programs only
// need the C standard library. Unsupported MIR never produces partial C.
struct c_program_result {
    string code
    string error
}

func c_program_fail(string error) c_program_result {
    return c_program_result { code: "", error: error }
}

func c_program_integer(int value) string {
    if value == 0 { return "0" }
    // Work in the negative range so INT64_MIN needs no overflowing negation.
    negative := value < 0
    remaining := value
    if remaining > 0 { remaining = 0 - remaining }
    text := ""
    for remaining < 0 {
        digit := 0 - (remaining % 10)
        ch := "0"
        if digit == 1 { ch = "1" }
        if digit == 2 { ch = "2" }
        if digit == 3 { ch = "3" }
        if digit == 4 { ch = "4" }
        if digit == 5 { ch = "5" }
        if digit == 6 { ch = "6" }
        if digit == 7 { ch = "7" }
        if digit == 8 { ch = "8" }
        if digit == 9 { ch = "9" }
        text = ch + text
        remaining = remaining / 10
    }
    if negative { return "-" + text }
    return text
}

func c_program_value(int id) string {
    return "v" + c_program_integer(id)
}

func c_program_function_name(int index) string {
    // Map symbols to unique numeric names instead of injecting package spelling
    // into C identifiers. Package identity is resolved by the MIR verifier.
    return "s_mir_f" + c_program_integer(index)
}

func c_program_return_type(mir_program_function function_data) string {
    if len(function_data.result_types) == 0 { return "void" }
    return "int64_t"
}

func c_program_parameters(mir_program_function function_data) string {
    if len(function_data.params) == 0 { return "void" }
    text := ""
    p := 0
    for p < len(function_data.params) {
        if p > 0 { text = text + ", " }
        text = text + "int64_t " + c_program_value(function_data.params[p].value_id)
        p = p + 1
    }
    return text
}

func c_program_arguments(int[] values) string {
    text := ""
    i := 0
    for i < len(values) {
        if i > 0 { text = text + ", " }
        text = text + c_program_value(values[i])
        i = i + 1
    }
    return text
}

func c_program_constant(int value) string {
    if value == -9223372036854775807 - 1 { return "INT64_MIN" }
    return "INT64_C(" + c_program_integer(value) + ")"
}

func c_program_instruction(mir_program program, mir_program_instruction ins) string {
    expression := ""
    if ins.op == "const_int" { expression = c_program_constant(ins.integer_value) }
    if ins.op == "copy" { expression = c_program_value(ins.operands[0]) }
    if ins.op == "add" || ins.op == "sub" || ins.op == "mul" || ins.op == "div" || ins.op == "mod" {
        expression = "s_mir_" + ins.op + "(" + c_program_arguments(ins.operands) + ")"
    }
    if ins.op == "call" {
        target := mir_program_function_index(program.functions, ins.symbol)
        expression = c_program_function_name(target) + "(" + c_program_arguments(ins.operands) + ")"
    }
    if len(ins.result_ids) == 0 { return "  " + expression + ";\n" }
    name := c_program_value(ins.result_ids[0])
    return "  int64_t " + name + " = " + expression + ";\n  (void)" + name + ";\n"
}

func c_program_function(mir_program program, int index) string {
    function_data := program.functions[index]
    text := c_program_return_type(function_data) + " " + c_program_function_name(index) + "(" + c_program_parameters(function_data) + ") {\n"
    p := 0
    for p < len(function_data.params) {
        text = text + "  (void)" + c_program_value(function_data.params[p].value_id) + ";\n"
        p = p + 1
    }
    block := function_data.blocks[0]
    i := 0
    for i < len(block.instructions) {
        text = text + c_program_instruction(program, block.instructions[i])
        i = i + 1
    }
    if len(block.return_values) == 0 {
        text = text + "  return;\n"
    } else {
        text = text + "  return " + c_program_value(block.return_values[0]) + ";\n"
    }
    return text + "}\n"
}

func c_program_prelude() string {
    // Explicit int64 wraparound, including division overflow. Division by zero
    // is a runtime error (exit 86), never a compile-time evaluation or fallback.
    return "#include <stdint.h>\n#include <stdlib.h>\n"
        + "static inline int64_t s_mir_bits(uint64_t v) { return v <= INT64_MAX ? (int64_t)v : -INT64_C(1) - (int64_t)(UINT64_MAX - v); }\n"
        + "static inline int64_t s_mir_add(int64_t a, int64_t b) { return s_mir_bits((uint64_t)a + (uint64_t)b); }\n"
        + "static inline int64_t s_mir_sub(int64_t a, int64_t b) { return s_mir_bits((uint64_t)a - (uint64_t)b); }\n"
        + "static inline int64_t s_mir_mul(int64_t a, int64_t b) { return s_mir_bits((uint64_t)a * (uint64_t)b); }\n"
        + "static inline int64_t s_mir_div(int64_t a, int64_t b) { if (b == 0) exit(86); if (a == INT64_MIN && b == -1) return INT64_MIN; return a / b; }\n"
        + "static inline int64_t s_mir_mod(int64_t a, int64_t b) { if (b == 0) exit(86); if (a == INT64_MIN && b == -1) return 0; return a % b; }\n"
}

func emit_mir_program_c(mir_program program) c_program_result {
    eprintln("TRACE emitter entry")
    first := program.functions[0]
    first_block := first.blocks[0]
    first_ins := first_block.instructions[0]
    eprintln(first_ins.op)
    trace_i := 0
    for trace_i < len(program.functions) {
        trace_fn := program.functions[trace_i]
        eprintln(trace_fn.symbol)
        trace_b := trace_fn.blocks[0]
        trace_n := 0
        for trace_n < len(trace_b.instructions) {
            trace_ins := trace_b.instructions[trace_n]
            eprintln(trace_ins.op)
            trace_n = trace_n + 1
        }
        trace_i = trace_i + 1
    }
    if program.package_name == "" { return c_program_fail("C codegen: empty package identity") }
    // Revalidate the actual input, including programs changed after lowering.
    functions := program.functions
    verified := lower_mir_program(program.package_name, program.entry_symbol, functions)
    eprintln("TRACE revalidation complete")
    if verified.error != "" { return c_program_fail(verified.error) }
    i := 0
    for i < len(program.functions) {
        function_data := program.functions[i]
        if function_data.external { return c_program_fail("C codegen: external linkage unsupported: " + function_data.symbol) }
        if len(function_data.result_types) > 1 { return c_program_fail("C codegen: multiple results unsupported: " + function_data.symbol) }
        if len(function_data.result_types) == 1 && function_data.result_types[0] != "int" {
            return c_program_fail("C codegen: unsupported result type: " + function_data.symbol)
        }
        p := 0
        for p < len(function_data.params) {
            if function_data.params[p].type_name != "int" { return c_program_fail("C codegen: unsupported parameter type: " + function_data.symbol) }
            p = p + 1
        }
        n := 0
        for n < len(function_data.blocks[0].instructions) {
            ins := function_data.blocks[0].instructions[n]
            r := 0
            for r < len(ins.result_types) {
                if ins.result_types[r] != "int" { return c_program_fail("C codegen: unsupported value type: " + function_data.symbol) }
                r = r + 1
            }
            n = n + 1
        }
        i = i + 1
    }
    text := c_program_prelude()
    eprintln("TRACE target validation complete")
    // Forward declarations preserve arbitrary function order and direct calls.
    i = 0
    for i < len(program.functions) {
        function_data := program.functions[i]
        text = text + c_program_return_type(function_data) + " " + c_program_function_name(i) + "(" + c_program_parameters(function_data) + ");\n"
        i = i + 1
    }
    i = 0
    for i < len(program.functions) {
        text = text + c_program_function(program, i)
        i = i + 1
    }
    entry_index := mir_program_function_index(program.functions, program.entry_symbol)
    entry := program.functions[entry_index]
    args := int[]()
    i = 0
    for i < len(entry.params) {
        args = append(args, entry.params[i].value_id)
        i = i + 1
    }
    text = text + c_program_return_type(entry) + " s_mir_entry(" + c_program_parameters(entry) + ") {\n  "
    if len(entry.result_types) == 1 { text = text + "return " }
    text = text + c_program_function_name(entry_index) + "(" + c_program_arguments(args) + ");\n}\n"
    return c_program_result { code: text, error: "" }
}
