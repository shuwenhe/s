package compile.internal


struct driver_config {
    string program_name
    string action
    string input
    string output
    string[] forwarded_args
    int exit_code
    string error
}

func driver_main(string[] args) int {
    config := parse_arguments(args)
    return dispatch_command(config)
}

func parse_arguments(string[] args) driver_config {
    config := driver_config {
        program_name: program_name(args),
        action: "",
        input: "",
        output: "",
        forwarded_args: string[]{},
        exit_code: 0,
        error: "",
    }
    if len(args) <= 1 {
        config.action = "usage"
        config.exit_code = 2
        return config
    }
    if len(args) == 2 && args[1] == "--help" {
        config.action = "help"
        return config
    }
    if len(args) == 4 && is_forwarded_mode(args[1]) {
        config.action = "forward"
        config.forwarded_args = args
        return config
    }
    if len(args) >= 2 && args[1] == "--seed" {
        config.action = "seed"
        config.forwarded_args = args
        return config
    }
    if len(args) == 5 && args[1] == "build" && args[3] == "-o" {
        config.action = "build"
        config.input = args[2]
        config.output = args[4]
        return config
    }
    if len(args) == 6 && args[1] == "build" && args[2] == "--legacy" && args[4] == "-o" {
        config.action = "legacy-build"
        config.input = args[3]
        config.output = args[5]
        return config
    }
    if len(args) == 4 && args[1] == "-o" {
        config.action = "build"
        config.input = args[3]
        config.output = args[2]
        return config
    }
    if len(args) >= 2 && is_option(args[1]) {
        config.action = "usage"
        config.exit_code = 2
        config.error = "unknown option: " + args[1]
        return config
    }
    if len(args) == 2 {
        config.action = "build"
        config.input = args[1]
        config.output = default_output(args[1])
        return config
    }
    if len(args) == 4 && args[2] == "-o" {
        config.action = "build"
        config.input = args[1]
        config.output = args[3]
        return config
    }
    config.action = "usage"
    config.exit_code = 2
    config.error = "invalid arguments"
    return config
}

func dispatch_command(driver_config config) int {
    if config.action == "help" {
        driver_print_usage(config.program_name)
        return 0
    }
    if config.action == "usage" {
        if config.error != "" {
            std.io.eprintln(config.program_name + ": " + config.error)
        }
        driver_print_usage(config.program_name)
        return config.exit_code
    }
    if config.action == "forward" {
        return compiler_main(config.forwarded_args)
    }
    if config.action == "build" {
        return pipeline_build(config.input, config.output, "", false)
    }
    if config.action == "legacy-build" {
        std.io.eprintln(config.program_name + ": build --legacy is handled by the bootstrap shell driver")
        return 2
    }
    if config.action == "seed" {
        std.io.eprintln(config.program_name + ": --seed is handled by the bootstrap shell driver")
        return 2
    }
    driver_print_usage(config.program_name)
    return 2
}

func program_name(string[] args) string {
    if len(args) == 0 || args[0] == "" {
        return "s"
    }
    return driver_basename(args[0])
}

func driver_basename(string path) string {
    last := 0
    i := 0
    while i < len(path) {
        if __string_char_at(path, i) == "/" {
            last = i + 1
        }
        i = i + 1
    }
    return __string_slice(path, last, len(path))
}

func default_output(string input) string {
    if has_suffix(input, ".s") {
        return __string_slice(input, 0, len(input) - 2)
    }
    return input + ".out"
}

func is_forwarded_mode(string mode) bool {
    if mode == "--emit-amd64" || mode == "--emit-amd64-executable" || mode == "--emit-native-object" { return true }
    if mode == "stage5-name-resolution-proof" || mode == "declaration-ref-proof" || mode == "type-checking-proof" { return true }
    if mode == "type-facts-observation-proof" || mode == "canonical-type-ref-proof" || mode == "canonical-semantic-proof" { return true }
    if mode == "canonical-lowering-proof" || mode == "canonical-mir-verification-proof" || mode == "canonical-ownership-proof" { return true }
    if mode == "canonical-monomorphization-proof" || mode == "canonical-optimization-proof" || mode == "canonical-layout-proof" { return true }
    if mode == "canonical-abi-proof" || mode == "canonical-codegen-proof" || mode == "canonical-regalloc-proof" { return true }
    if mode == "--emit-c" { return true }
    if mode == "--emit-lowered-view" { return true }
    if mode == "--emit-mir" { return true }
    if mode == "--emit-mir-after-drop" { return true }
    if mode == "--emit-mir-place" { return true }
    if mode == "--emit-mir-movepath" { return true }
    if mode == "--emit-mir-partial-move" { return true }
    if mode == "--emit-mir-reinit" { return true }
    if mode == "--emit-mir-partial-drop" { return true }
    if mode == "--emit-mir-place-borrow" { return true }
    if mode == "--emit-mir-reference-liveness" { return true }
    if mode == "--emit-mir-loan-liveness" { return true }
    if mode == "--emit-mir-region-constraints" { return true }
    if mode == "--emit-mir-region-solver" { return true }
    if mode == "--emit-mir-nll-borrow-check" { return true }
    if mode == "--emit-mir-nll-shadow" { return true }
    if mode == "--emit-mir-nll-real-cfg" { return true }
    if mode == "--emit-mir-ownership-solver-check" { return true }
    if mode == "--emit-mir-nll-ownership" { return true }
    return false
}

func driver_proof_modes() string[] {
    return ["stage5-name-resolution-proof", "declaration-ref-proof", "type-checking-proof",
        "type-facts-observation-proof", "canonical-type-ref-proof", "canonical-semantic-proof",
        "canonical-lowering-proof", "canonical-mir-verification-proof", "canonical-ownership-proof",
        "canonical-monomorphization-proof", "canonical-optimization-proof", "canonical-layout-proof",
        "canonical-abi-proof", "canonical-codegen-proof", "canonical-regalloc-proof"]
}

func has_suffix(string text, string suffix) bool {
    if len(suffix) > len(text) {
        return false
    }
    return __string_slice(text, len(text) - len(suffix), len(text)) == suffix
}

func is_option(string arg) bool {
    if len(arg) == 0 {
        return false
    }
    return __string_slice(arg, 0, 1) == "-"
}

func driver_print_usage(string prog) () {
    std.io.eprintln("usage:")
    std.io.eprintln("  " + prog + " <input.s>")
    std.io.eprintln("  " + prog + " <input.s> -o <output>")
    std.io.eprintln("  " + prog + " -o <output> <input.s>")
    std.io.eprintln("  " + prog + " build <input.s> -o <output>")
    std.io.eprintln("  " + prog + " --emit-c <input.s> <output.c>")
    std.io.eprintln("  " + prog + " --emit-mir <input.s> <output.mir>")
    std.io.eprintln("  " + prog + " --emit-amd64 <input.s> <output.s>")
    std.io.eprintln("  " + prog + " --emit-native-object <input.s> <output.o>")
    std.io.eprintln("  " + prog + " <proof-mode> <input.s> <output.proof>")
}

extern "intrinsic" func __string_char_at(string text, int index) string
extern "intrinsic" func __string_slice(string text, int start, int end) string
