package cmd
import (
    "compile.internal.semantic"
    "compile.internal.syntax"
    "compile.internal.tests.test_backend_abi"
    "compile.internal.tests.test_golden"
    "compile.internal.tests.test_mir"
    "compile.internal.tests.test_pipeline_regression"
    "compile.internal.tests.test_semantic"
    "compile.internal.tests.test_ssa"
    "compile.internal.tests.test_typesys"
    "std.io"
)

func main() int {
    args := host_args()
    if len(args) == 2 && args[1] == "--help" {
        print_usage()
        return 0
    }
    if len(args) < 2 {
        print_usage()
        return 2
    }
    buildcfg_err := buildcfg_check()
    if buildcfg_err != "" {
        std.io.eprintln("compile: " + buildcfg_err)
        return 2
    }
    goarch := buildcfg_goarch()
    arch_err := arch_dispatch_init(goarch)
    if arch_err != "" {
        std.io.eprintln("compile: " + arch_err)
        return 2
    }
    command := args[1]
    if command == "build" {
        if len(args) != 5 || args[3] != "-o" {
            print_usage()
            return 2
        }
        return build_elf64(args[2], args[4], "", false)
    }
    if command == "check" {
        if len(args) != 3 {
            print_usage()
            return 2
        }
        return run_check(args[2])
    }
    if command == "tokens" {
        if len(args) != 3 {
            print_usage()
            return 2
        }
        return run_tokens(args[2])
    }
    if command == "ast" {
        if len(args) != 3 {
            print_usage()
            return 2
        }
        return run_ast(args[2])
    }
    if command == "test" {
        if len(args) == 3 {
            return run_tests(args[2])
        }
        return run_tests("src/cmd/compile/internal/tests/fixtures")
    }
    print_usage()
    return 2
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
