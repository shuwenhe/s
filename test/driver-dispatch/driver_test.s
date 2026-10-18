package compile.driver

// Keep the real argument parser and dispatcher. The compiler and native backend
// are replaced at their call boundaries so their unrelated bootstrap state
// cannot hide a wrong target, lost argument, or ignored exit status.
func compiler_main(string[] args) int {
    if len(args) != 4 || args[2] != "input.s" || args[3] != "output" { return 81 }
    return 37
}

func pipeline_build(string input, string output, string margin, bool nostdlib) int {
    if input != "input.s" || output != "output" || margin != "" || nostdlib { return 82 }
    return 29
}

func proof_modes() string[] {
    return ["stage5-name-resolution-proof", "declaration-ref-proof", "type-checking-proof",
        "type-facts-observation-proof", "canonical-type-ref-proof", "canonical-semantic-proof",
        "canonical-lowering-proof", "canonical-mir-verification-proof", "canonical-ownership-proof",
        "canonical-monomorphization-proof", "canonical-optimization-proof", "canonical-layout-proof",
        "canonical-abi-proof", "canonical-codegen-proof", "canonical-regalloc-proof"]
}

func forwarded_modes() string[] {
    modes := proof_modes()
    modes.push("--emit-amd64")
    modes.push("--emit-amd64-executable")
    modes.push("--emit-native-object")
    return modes
}

func check_parse() int {
    modes := forwarded_modes()
    i := 0
    for i < len(modes) {
        mode := modes[i]
        config := parse_arguments(["s", mode, "input.s", "output"])
        if config.action != "forward" || len(config.forwarded_args) != 4 {
            eprintln("proof command was not forwarded: " + modes[i])
            return 1
        }
        if config.forwarded_args[1] != modes[i] || config.forwarded_args[2] != "input.s" || config.forwarded_args[3] != "output" {
            eprintln("proof command arguments were changed: " + modes[i])
            return 2
        }
        i = i + 1
    }
    if parse_arguments(["s", "canonical-layout-proof", "input.s"]).action != "usage" { return 3 }
    if parse_arguments(["s", "unknown-proof", "input.s", "output"]).action != "usage" { return 4 }
    if parse_arguments(["s", "--help"]).action != "help" { return 5 }
    return 0
}

func check_dispatch() int {
    if driver_main(["s", "--emit-c", "input.s", "output"]) != 37 {
        eprintln("emit command did not return compiler_main status")
        return 1
    }
    modes := forwarded_modes()
    i := 0
    for i < len(modes) {
        mode := modes[i]
        if driver_main(["s", mode, "input.s", "output"]) != 37 {
            eprintln("proof command did not return compiler_main status: " + modes[i])
            return 2
        }
        i = i + 1
    }
    if driver_main(["s", "build", "input.s", "-o", "output"]) != 29 { return 3 }
    if driver_main(["s", "--unknown"]) != 2 { return 4 }
    return 0
}

func main() int {
    args := host_args()
    if len(args) == 2 && args[1] == "test-parse" { return check_parse() }
    if len(args) == 2 && args[1] == "test-dispatch" { return check_dispatch() }
    return driver_main(args)
}
