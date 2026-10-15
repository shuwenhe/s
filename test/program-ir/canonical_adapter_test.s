package program_ir_canonical_test

import (
    "compile.internal.parser.syntax"
    "compile.internal.ir.lower"
    "std"
)

// Intended integration test for a canonical test executor. This is not used
// to claim that the hosted module test reached Parser/Semantic or native code.
func main() int {
    source := "package sample\nfunc add(int a, int b) int { return a + b }\nfunc main() int { return add(3, 4) }\n"
    parsed := compile.internal.parser.syntax.parse_source(source)
    if parsed.is_err() { return 1 }
    program := compile.internal.ir.lower.lower_program_to_mir(parsed.unwrap())
    if program.error != "" { return 2 }
    if len(program.program.functions) != 2 { return 3 }
    if program.program.functions[0].symbol != "sample.add" { return 4 }
    if len(program.program.functions[0].params) != 2 { return 5 }
    if program.program.functions[0].blocks[0].instructions[0].op != "add" { return 6 }
    if len(program.program.calls) != 1 { return 7 }
    if program.program.calls[0].callee != "sample.add" { return 8 }

    typed_source := "package sample\nfunc main() int { bool x = 1; return x }\n"
    typed := compile.internal.parser.syntax.parse_source(typed_source)
    if typed.is_err() { return 9 }
    typed_program := compile.internal.ir.lower.lower_program_to_mir(typed.unwrap())
    if typed_program.error != "local type mismatch: x" { return 10 }

    void_source := "package sample\nfunc f() {}\nfunc main() { return f() }\n"
    void_parsed := compile.internal.parser.syntax.parse_source(void_source)
    if void_parsed.is_err() { return 11 }
    void_program := compile.internal.ir.lower.lower_program_to_mir(void_parsed.unwrap())
    if void_program.error != "unexpected return value: sample.main" { return 12 }
    return 0
}
