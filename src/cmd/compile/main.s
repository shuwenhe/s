package cmd
import (
    // Self-hosted bootstrap aggregate packages
    // These enable import-driven bootstrap (Go-style)
    "cmd.compile.frontend.selfhost"
    "cmd.compile.middlend.selfhost"
    "cmd.compile.backend.selfhost"
    
    // Regular compiler components
    "compile.internal.backend_elf64"
    "compile.internal.semantic"
    "compile.internal.syntax"
    "compile.internal.tests.test_backend_abi"
    "compile.internal.tests.test_golden"
    "compile.internal.tests.test_mir"
    "compile.internal.tests.test_pipeline_regression"
    "compile.internal.tests.test_semantic"
    "compile.internal.tests.test_ssa"
    "compile.internal.tests.test_typesys"
    "internal.buildcfg"
    "compile.internal.arch"
    "std.env"
    "std.io"
    "std.process"
)

func main() {
    args := std.env.args()
    if len(args) == 2 && args[1] == "--help" {
        print_usage()
        std.process.exit(0)
    }
    if len(args) < 2 {
        print_usage()
        std.process.exit(2)
    }
    buildcfg_err := internal.buildcfg.check()
    if buildcfg_err != "" {
        std.io.eprintln("compile: " + buildcfg_err)
        std.process.exit(2)
    }
    goarch := internal.buildcfg.goarch()
    arch_err := compile.internal.arch.dispatch_init(goarch)
    if arch_err != "" {
        std.io.eprintln("compile: " + arch_err)
        std.process.exit(2)
    }
    command := args[1]
    if command == "build" {
        if len(args) != 5 || args[3] != "-o" {
            print_usage()
            std.process.exit(2)
        }
        std.process.exit(compile.internal.backend_elf64.build(args[2], args[4], "", false))
    }
    if command == "check" {
        if len(args) != 3 {
            print_usage()
            std.process.exit(2)
        }
        std.process.exit(run_check(args[2]))
    }
    if command == "tokens" {
        if len(args) != 3 {
            print_usage()
            std.process.exit(2)
        }
        std.process.exit(run_tokens(args[2]))
    }
    if command == "ast" {
        if len(args) != 3 {
            print_usage()
            std.process.exit(2)
        }
        std.process.exit(run_ast(args[2]))
    }
    if command == "test" {
        if len(args) == 3 {
            std.process.exit(run_tests(args[2]))
        }
        std.process.exit(run_tests("src/cmd/compile/internal/tests/fixtures"))
    }
    print_usage()
    std.process.exit(2)
}

func print_usage() () {
    std.io.eprintln("usage: s_modular check <input.s>")
    std.io.eprintln("       s_modular tokens <input.s>")
    std.io.eprintln("       s_modular ast <input.s>")
    std.io.eprintln("       s_modular build <input.s> -o <output>")
    std.io.eprintln("       s_modular test [fixtures_root]")
}

func run_check(string path) int {
    source_result := compile.internal.syntax.read_source(path)
    if source_result.is_err() {
        return 1
    }
    source := source_result.unwrap()
    parsed := compile.internal.syntax.parse_source(source)
    if parsed.is_err() {
        return 1
    }
    if compile.internal.semantic.check_text(source) != 0 {
        return 1
    }
    std.io.eprintln("check ok: " + path)
    return 0
}

func run_tokens(string path) int {
    source_result := compile.internal.syntax.read_source(path)
    if source_result.is_err() {
        return 1
    }
    tokens := compile.internal.syntax.tokenize(source_result.unwrap())
    if tokens.is_err() {
        return 1
    }
    std.io.eprintln("tokens ok: " + path)
    return 0
}

func run_ast(string path) int {
    source_result := compile.internal.syntax.read_source(path)
    if source_result.is_err() {
        return 1
    }
    parsed := compile.internal.syntax.parse_source(source_result.unwrap())
    if parsed.is_err() {
        return 1
    }
    std.io.eprintln("ast ok: " + path)
    return 0
}

func run_tests(string fixtures_root) int {
    if compile.internal.tests.test_semantic.run_semantic_suite(fixtures_root) != 0 {
        std.io.eprintln("semantic suite failed")
        return 1
    }
    if compile.internal.tests.test_golden.run_golden_suite(fixtures_root) != 0 {
        std.io.eprintln("golden suite failed")
        return 1
    }
    if compile.internal.tests.test_backend_abi.run_backend_abi_suite() != 0 {
        std.io.eprintln("backend abi suite failed")
        return 1
    }
    if compile.internal.tests.test_mir.run_mir_suite() != 0 {
        std.io.eprintln("mir suite failed")
        return 1
    }
    if compile.internal.tests.test_ssa.run_ssa_suite() != 0 {
        std.io.eprintln("ssa suite failed")
        return 1
    }
    if compile.internal.tests.test_pipeline_regression.run_pipeline_regression_suite() != 0 {
        std.io.eprintln("pipeline regression suite failed")
        return 1
    }
    if compile.internal.tests.test_typesys.run_typesys_suite() != 0 {
        std.io.eprintln("typesys suite failed")
        return 1
    }
    std.io.eprintln("test: ok")
    return 0
}

// SELFHOST_MAIN_BEGIN
// The native self-host bootstrap materializer extracts this block, strips the
// comment prefix, and rewrites selfhost_main back to main when rebuilding the
// historical single-file bootstrap source.
// SELFHOST_MAIN_LINE         return 1
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     return 0
// SELFHOST_MAIN_LINE }
// SELFHOST_MAIN_LINE 
// SELFHOST_MAIN_LINE func compile_native_binary(string source, string output_path) int {
// SELFHOST_MAIN_LINE     string elf = emit_native_auto_elf(source)
// SELFHOST_MAIN_LINE     if elf == "" {
// SELFHOST_MAIN_LINE         eprintln("compile: source is outside implemented native slices")
// SELFHOST_MAIN_LINE         return 1
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     if __host_write_text_file(output_path, elf) != 0 || __host_make_executable(output_path) != 0 {
// SELFHOST_MAIN_LINE         eprintln("compile: cannot write native executable")
// SELFHOST_MAIN_LINE         return 1
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     return 0
// SELFHOST_MAIN_LINE }
// SELFHOST_MAIN_LINE 
// SELFHOST_MAIN_LINE func file_extension(string path) string {
// SELFHOST_MAIN_LINE     int dot = -1
// SELFHOST_MAIN_LINE     int index = len(path) - 1
// SELFHOST_MAIN_LINE     while index >= 0 {
// SELFHOST_MAIN_LINE         if __host_char_at(path, index) == "." {
// SELFHOST_MAIN_LINE             dot = index
// SELFHOST_MAIN_LINE             break
// SELFHOST_MAIN_LINE         }
// SELFHOST_MAIN_LINE         if __host_char_at(path, index) == "/" {
// SELFHOST_MAIN_LINE             break
// SELFHOST_MAIN_LINE         }
// SELFHOST_MAIN_LINE         index = index - 1
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     if dot < 0 { return "" }
// SELFHOST_MAIN_LINE     return __host_slice(path, dot, len(path))
// SELFHOST_MAIN_LINE }
// SELFHOST_MAIN_LINE 
// SELFHOST_MAIN_LINE func default_output_path(string path) string {
// SELFHOST_MAIN_LINE     int index = len(path) - 1
// SELFHOST_MAIN_LINE     while index >= 0 {
// SELFHOST_MAIN_LINE         if __host_char_at(path, index) == "." {
// SELFHOST_MAIN_LINE             return __host_slice(path, 0, index)
// SELFHOST_MAIN_LINE         }
// SELFHOST_MAIN_LINE         if __host_char_at(path, index) == "/" {
// SELFHOST_MAIN_LINE             break
// SELFHOST_MAIN_LINE         }
// SELFHOST_MAIN_LINE         index = index - 1
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     return path + ".out"
// SELFHOST_MAIN_LINE }
// SELFHOST_MAIN_LINE 
// SELFHOST_MAIN_LINE func selfhost_main() {
// SELFHOST_MAIN_LINE     args := host_args()
// SELFHOST_MAIN_LINE     if len(args) == 2 && args[1] == "--help" {
// SELFHOST_MAIN_LINE         eprintln("usage: s <input.s> [-o <output>] (default: a.out)")
// SELFHOST_MAIN_LINE         eprintln("       s -o <output> <input.s>")
// SELFHOST_MAIN_LINE         eprintln("       s build <input.s> -o <output>")
// SELFHOST_MAIN_LINE         return 0
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     if len(args) == 3 && (args[1] == "-o" || args[2] == "-o") {
// SELFHOST_MAIN_LINE         eprintln("compile: -o requires an output path and an input file")
// SELFHOST_MAIN_LINE         return 2
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     bool direct_default = len(args) == 2 && file_extension(args[1]) == ".s"
// SELFHOST_MAIN_LINE     bool direct_output = len(args) == 4 && args[2] == "-o"
// SELFHOST_MAIN_LINE     bool output_first = len(args) == 4 && args[1] == "-o"
// SELFHOST_MAIN_LINE     bool build_native = len(args) == 5 && args[1] == "build" && args[3] == "-o"
// SELFHOST_MAIN_LINE     if (len(args) != 3 && len(args) != 4 && !build_native && !direct_default) {
// SELFHOST_MAIN_LINE         eprintln("usage: s <input.s> [-o <output>] (default: a.out)")
// SELFHOST_MAIN_LINE         eprintln("       s build <input.s> -o <output>")
// SELFHOST_MAIN_LINE         return 2
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     bool report_unsupported = len(args) == 4 && args[1] == "--report-unsupported"
// SELFHOST_MAIN_LINE     bool binary = len(args) == 4 && args[1] == "--emit-bin"
// SELFHOST_MAIN_LINE     bool native_expression = len(args) == 4 && args[1] == "--emit-native-expr"
// SELFHOST_MAIN_LINE     bool native_control = len(args) == 4 && args[1] == "--emit-native-control"
// SELFHOST_MAIN_LINE     bool native_locals = len(args) == 4 && args[1] == "--emit-native-locals"
// SELFHOST_MAIN_LINE     bool native_call = len(args) == 4 && args[1] == "--emit-native-call"
// SELFHOST_MAIN_LINE     bool native_loop = len(args) == 4 && args[1] == "--emit-native-loop"
// SELFHOST_MAIN_LINE     bool native_string = len(args) == 4 && args[1] == "--emit-native-string"
// SELFHOST_MAIN_LINE     bool native = (len(args) == 4 && args[1] == "--emit-native") || build_native || direct_default || direct_output || output_first
// SELFHOST_MAIN_LINE     bool native_array = len(args) == 4 && args[1] == "--emit-native-array"
// SELFHOST_MAIN_LINE     bool native_multi_call = len(args) == 4 && args[1] == "--emit-native-multicall"
// SELFHOST_MAIN_LINE     bool native_copy = len(args) == 4 && args[1] == "--emit-native-copy"
// SELFHOST_MAIN_LINE     bool native_assembly = len(args) == 4 && args[1] == "--emit-asm"
// SELFHOST_MAIN_LINE     bool darwin_arm64_assembly = len(args) == 4 && args[1] == "--emit-asm-darwin-arm64"
// SELFHOST_MAIN_LINE     bool selfhost_c = len(args) == 4 && args[1] == "--emit-c"
// SELFHOST_MAIN_LINE     bool debug_find = len(args) == 4 && args[1] == "--debug-find"
// SELFHOST_MAIN_LINE     int input_index = 1
// SELFHOST_MAIN_LINE     int output_index = 2
// SELFHOST_MAIN_LINE     if build_native {
// SELFHOST_MAIN_LINE         input_index = 2
// SELFHOST_MAIN_LINE         output_index = 4
// SELFHOST_MAIN_LINE     } else if report_unsupported || binary || native_expression || native_control || native_locals || native_call || native_loop || native_string || native || native_array || native_multi_call || native_copy || native_assembly || darwin_arm64_assembly || selfhost_c || debug_find {
// SELFHOST_MAIN_LINE         input_index = 2
// SELFHOST_MAIN_LINE         output_index = 3
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     if direct_output { input_index = 1; output_index = 3 }
// SELFHOST_MAIN_LINE     if output_first { input_index = 3; output_index = 2 }
// SELFHOST_MAIN_LINE     if direct_default { input_index = 1 }
// SELFHOST_MAIN_LINE     if len(args) == 4 && input_index == 1 && !direct_output {
// SELFHOST_MAIN_LINE         eprintln("compile: unknown option or invalid arguments")
// SELFHOST_MAIN_LINE         return 2
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     string output_path = "a.out"
// SELFHOST_MAIN_LINE     if !direct_default { output_path = args[output_index] }
// SELFHOST_MAIN_LINE     if output_path == args[input_index] {
// SELFHOST_MAIN_LINE         eprintln("compile: input and output paths must differ")
// SELFHOST_MAIN_LINE         return 2
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     string source = __host_read_to_string(args[input_index])
// SELFHOST_MAIN_LINE     if len(source) == 0 {
// SELFHOST_MAIN_LINE         eprintln("compile: cannot read input or input is empty")
// SELFHOST_MAIN_LINE         return 1
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     if selfhost_c { return compile_selfhost_c(source, output_path) }
// SELFHOST_MAIN_LINE     if debug_find {
// SELFHOST_MAIN_LINE         int found = find_function_from(source, 0)
// SELFHOST_MAIN_LINE         int body = function_body(source, "main")
// SELFHOST_MAIN_LINE         return __host_write_text_file(output_path, int_text(found) + "|" + int_text(body))
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     if !native_assembly && !darwin_arm64_assembly && parse_package_name(source) == "" {
// SELFHOST_MAIN_LINE         eprintln("compile: invalid or missing package declaration")
// SELFHOST_MAIN_LINE         return 1
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     if !native_assembly && !darwin_arm64_assembly && intrinsic_declaration_count(source) < 0 {
// SELFHOST_MAIN_LINE         eprintln("compile: invalid extern intrinsic declaration")
// SELFHOST_MAIN_LINE         return 1
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     if !native_assembly && !darwin_arm64_assembly && !debug_find && !validate_function_symbols(source) {
// SELFHOST_MAIN_LINE         eprintln("compile: invalid function symbol table")
// SELFHOST_MAIN_LINE         return 1
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     if report_unsupported {
// SELFHOST_MAIN_LINE         if __host_write_text_file(output_path, unsupported_report(source)) != 0 {
// SELFHOST_MAIN_LINE             eprintln("compile: cannot write unsupported capability report")
// SELFHOST_MAIN_LINE             return 1
// SELFHOST_MAIN_LINE         }
// SELFHOST_MAIN_LINE         return 0
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     if binary {
// SELFHOST_MAIN_LINE         return compile_binary(source, output_path)
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     if native_expression {
// SELFHOST_MAIN_LINE         return compile_native_expression_binary(source, output_path)
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     if native_control {
// SELFHOST_MAIN_LINE         return compile_native_control_binary(source, output_path)
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     if native_locals {
// SELFHOST_MAIN_LINE         return compile_native_locals_binary(source, output_path)
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     if native_call {
// SELFHOST_MAIN_LINE         return compile_native_call_binary(source, output_path)
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     if native_loop {
// SELFHOST_MAIN_LINE         return compile_native_loop_binary(source, output_path)
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     if native_string {
// SELFHOST_MAIN_LINE         return compile_native_string_binary(source, output_path)
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     if native {
// SELFHOST_MAIN_LINE         return compile_native_binary(source, output_path)
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     if native_array {
// SELFHOST_MAIN_LINE         return compile_native_array_binary(source, output_path)
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     if native_multi_call {
// SELFHOST_MAIN_LINE         return compile_native_multi_call_binary(source, output_path)
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     if native_copy {
// SELFHOST_MAIN_LINE         return compile_native_copy_binary(source, output_path)
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     if native_assembly {
// SELFHOST_MAIN_LINE         return compile_native_assembly(source, output_path)
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     if darwin_arm64_assembly {
// SELFHOST_MAIN_LINE         return compile_darwin_arm64_assembly(source, output_path)
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     string ir = compile_main_expression(source)
// SELFHOST_MAIN_LINE     if len(ir) == 0 {
// SELFHOST_MAIN_LINE         eprintln("compile: source is outside bootstrap slice 1")
// SELFHOST_MAIN_LINE         return 1
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     if __host_write_text_file(output_path, ir) != 0 {
// SELFHOST_MAIN_LINE         eprintln("compile: cannot write output")
// SELFHOST_MAIN_LINE         return 1
// SELFHOST_MAIN_LINE     }
// SELFHOST_MAIN_LINE     return 0
// SELFHOST_MAIN_LINE }
// SELFHOST_MAIN_LINE 
// SELFHOST_MAIN_END
