package native_frontend_test

func frontend_check(bool condition, string message) int {
    if !condition { eprintln(message); return 1 }
    return 0
}

func check_native_call_shadowing() int {
    rejected := [
        "package shadow func helper(int value) int { return value + 1 } func main(int helper) int { return helper(2) }",
        "package shadow func helper(int value) int { return value + 1 } func main(int input) int { helper := input; return helper(2) }",
        "package shadow func helper(int value) int { return value + 1 } func main() int { int helper = 9; return helper(2) }",
        "package shadow func helper(int value) int { return value + 1 } func main() int { helper := 9; helper(2); return 0 }",
        "package shadow func helper(int value) int { return value + 1 } func main() int { shadow := 9; return shadow.helper(2) }",
        "package shadow func helper(int value) int { return value + 1 } func main(int shadow) int { return shadow.helper(2) }"
    ];
    expected_roots := ["helper", "helper", "helper", "helper", "shadow", "shadow"];
    i := 0
    for i < len(rejected) {
        result := native_source_to_mir(rejected[i])
        if !compiler_contains_text(result.error, "integer binding is not callable: " + expected_roots[i]) {
            eprintln("shadowed call was not rejected at its binding: " + result.error)
            return 80 + i
        }
        if len(result.program.functions) != 0 || len(result.program.calls) != 0 { return 86 }
        i = i + 1
    }
    // A new binding starts after its initializer; the earlier function remains
    // callable there. Reusing a function name for an integer value is legal.
    accepted := [
        "package shadow func helper(int value) int { return value + 1 } func main(int input) int { helper := helper(input); return helper }",
        "package shadow func helper(int value) int { return value + 1 } func main(int helper) int { return helper + 2 }",
        "package shadow func helper(int value) int { return value + 1 } func main(int input) int { helper := input; return shadow.helper(helper) }"
    ];
    i = 0
    for i < len(accepted) {
        valid := native_source_to_mir(accepted[i])
        if valid.error != "" { eprintln(valid.error); return 87 + i }
        i = i + 1
    }
    return 0
}

func check_native_review_regressions() int {
    keyword_sources := [
        "package bad func main() int { switch := 1; return switch }",
        "package bad func switch() int { return 1 } func main() int { return switch() }",
        "package bad func main(int var) int { return var }",
        "package bad func main() int { const := 1; return const }",
        "package bad func trait() int { return 1 } func main() int { return trait() }",
        "package bad func main(int nil) int { return nil }",
        "package unsafe func main() int { return 1 }",
        "package bad.where func main() int { return 1 }"
    ];
    i := 0
    for i < len(keyword_sources) {
        result := native_source_to_mir(keyword_sources[i])
        if result.error == "" { eprintln("reserved keyword accepted as identifier: " + keyword_sources[i]); return 60 + i }
        i = i + 1
    }
    padded_min := native_source_to_mir("package padded func main() int { return -09223372036854775808 }")
    if padded_min.error != "" { eprintln(padded_min.error); return 70 }
    if padded_min.program.functions[0].blocks[0].instructions[0].integer_value != -9223372036854775807 - 1 { return 71 }
    more_padding := native_source_to_mir("package padded func main() int { return -0009223372036854775808 }")
    if more_padding.error != "" { eprintln(more_padding.error); return 72 }
    overflow := native_source_to_mir("package padded func main() int { return -0009223372036854775809 }")
    if overflow.error == "" { eprintln("padded negative literal overflow accepted"); return 73 }
    return 0
}

func check_native_frontend(string source) int {
    shadowing := check_native_call_shadowing()
    if shadowing != 0 { return shadowing }
    reviewed := check_native_review_regressions()
    if reviewed != 0 { return reviewed }
    result := native_source_to_mir(source)
    if result.error != "" { eprintln(result.error); return 1 }
    program := result.program
    if frontend_check(program.package_name == "sample.native" && program.entry_symbol == "sample.native.main", "package identity lost") != 0 { return 2 }
    if frontend_check(len(program.functions) == 5, "unused functions lost") != 0 { return 3 }
    if frontend_check(program.functions[1].symbol == "sample.native.unused", "function order changed") != 0 { return 4 }
    params := program.functions[1].params
    if frontend_check(len(params) == 2 && params[0].name == "first" && params[1].name == "second" && params[0].value_id == 0 && params[1].value_id == 1, "parameter order lost") != 0 { return 5 }
    if frontend_check(len(program.calls) == 3 && program.calls[0].callee == "sample.native.later" && program.calls[1].callee == "sample.native.effect" && program.calls[2].callee == "sample.native.final", "forward call targets lost") != 0 { return 6 }
    instructions := program.functions[0].blocks[0].instructions
    division := false
    modulo := false
    i := 0
    for i < len(instructions) {
        if instructions[i].op == "div" { division = true }
        if instructions[i].op == "mod" { modulo = true }
        i = i + 1
    }
    if frontend_check(division && modulo, "runtime division was evaluated or lost") != 0 { return 7 }
    void_call := program.functions[2].blocks[0].instructions[0]
    if frontend_check(void_call.op == "call" && len(void_call.result_ids) == 0, "void call lost") != 0 { return 8 }
    if frontend_check(len(program.functions[3].blocks[0].return_values) == 0, "void return changed") != 0 { return 9 }
    changed := native_source_to_mir("package changed func main(int input) int { return changed.next(input) } func next(int argument) int { return argument * 19 }")
    if changed.error != "" { eprintln(changed.error); return 10 }
    changed_instructions := changed.program.functions[1].blocks[0].instructions
    if frontend_check(changed_instructions[0].integer_value == 19 && changed_instructions[1].op == "mul", "source mutation not reflected in MIR") != 0 { return 11 }
    minimum := native_source_to_mir("package minimum func main() int { return -9223372036854775808 }")
    if minimum.error != "" { eprintln(minimum.error); return 12 }
    if frontend_check(minimum.program.functions[0].blocks[0].instructions[0].integer_value == -9223372036854775807 - 1, "minimum int64 literal lost") != 0 { return 13 }
    many := "package many func main() int { return f19(7) } "
    n := 0
    for n < 20 {
        many = many + "func f" + compiler_number(n) + "(int value) int { return value + " + compiler_number(n) + " } "
        n = n + 1
    }
    expanded := native_source_to_mir(many)
    if expanded.error != "" { eprintln(expanded.error); return 14 }
    if frontend_check(len(expanded.program.functions) == 21, "fixed function capacity imposed") != 0 { return 15 }
    rejected := [
        "package bad func main() int { return missing(1) }",
        "package bad func main() int { return later(1) } func later(int a, int b) int { return a }",
        "package bad func main() int { return absent }",
        "package bad func main() int { x := 1; x := 2; return x }",
        "package bad func main(int x, int x) int { return x }",
        "package bad func main() int { return 1 } func main() int { return 2 }",
        "package bad func main() int { return 1 } trailing",
        "package bad import \"std\" func main() int { return 1 }",
        "package bad extern \"C\" func x() int; func main() int { return x() }",
        "package bad func main() int { if 1 { return 1 } return 0 }",
        "package bad func main() int { return empty() } func empty() {}",
        "package bad func main(string value) int { return 1 }",
        "package bad func main() int { return 9223372036854775808 }",
        "package bad func main() int { int x = 2 }",
        "package bad func main() int { return 1; x := 2 }",
        "package bad func main() int { return 1 } /* unfinished"
    ]
    i = 0
    for i < len(rejected) {
        invalid := native_source_to_mir(rejected[i])
        if invalid.error == "" { eprintln("unsupported source accepted: " + rejected[i]); return 20 + i }
        i = i + 1
    }
    return 0
}

func main() int {
    args := host_args()
    if len(args) != 2 { return 90 }
    source := __host_read_to_string(args[1])
    status := check_native_frontend(source)
    if status == 0 { println("Structured native frontend: PASS") }
    return status
}
