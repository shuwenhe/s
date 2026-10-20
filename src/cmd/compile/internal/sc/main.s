package cmd

import (
    "compile.internal.pipeline"
    "compile.internal.semantic"
    "compile.internal.syntax"
    "compile.internal.tests.test_backend_abi"
    "compile.internal.tests.test_golden"
    "compile.internal.tests.test_driver"
    "compile.internal.tests.test_mir"
    "compile.internal.tests.test_pipeline_regression"
    "compile.internal.tests.test_semantic"
    "compile.internal.tests.test_ssa"
    "compile.internal.tests.test_typesys"
    "internal.buildcfg"
    "compile.internal.arch"
    "std.conv"
    "std.env"
    "std.io"
    "std.process"
)

struct compiler_options {
    bool timing
    bool stats
    bool dump_ast
    bool nostdlib
    string ssa_margin_override
}

struct compile_stats {
    string command
    string input
    string output
    string goarch
    int exit_status
    int elapsed_ns
}

struct compile_init_result {
    string goarch
    string error
}

func main() {
    start_ns := __runtime_nanotime()
    args := std.env.args()
    status := run_compile_main(args, start_ns)
    process_exit(status)
}

func run_compile_main(string[] args, int start_ns) int {
    options := default_options()
    if len(args) == 2 && args[1] == "--help" {
        print_usage()
        return 0
    }
    if len(args) < 2 {
        print_usage()
        return 2
    }

    init := init_compile_environment()
    if init.error != "" {
        std.io.eprintln("compile: " + init.error)
        return 2
    }

    return run_command(args, options, init.goarch, start_ns)
}

func init_compile_environment() compile_init_result {
    buildcfg_err := internal.buildcfg.check()
    if buildcfg_err != "" {
        return compile_init_result {
            goarch: "",
            error: buildcfg_err,
        }
    }
    goarch := internal.buildcfg.goarch()
    arch_err := compile.internal.arch.dispatch_init(goarch)
    if arch_err != "" {
        return compile_init_result {
            goarch: goarch,
            error: arch_err,
        }
    }
    return compile_init_result {
        goarch: goarch,
        error: "",
    }
}

func run_command(string[] args, compiler_options options, string goarch, int start_ns) int {
    opts := options
    command := args[1]
    if command == "build" {
        if len(args) < 5 || args[3] != "-o" {
            return usage_error("build expects: build <input.s> -o <output> [options]")
        }
        opts = parse_build_options(args, 5, opts)
        status := run_build(args[2], args[4], opts)
        finish_command(build_stats(command, args[2], args[4], goarch, status, start_ns), opts)
        return status
    }
    if command == "check" {
        if len(args) < 3 {
            return usage_error("check expects: check <input.s> [options]")
        }
        opts = parse_common_options(args, 3, opts)
        status := run_check(args[2], opts)
        finish_command(build_stats(command, args[2], "", goarch, status, start_ns), opts)
        return status
    }
    if command == "tokens" {
        if len(args) < 3 {
            return usage_error("tokens expects: tokens <input.s> [options]")
        }
        opts = parse_common_options(args, 3, opts)
        status := run_tokens(args[2])
        finish_command(build_stats(command, args[2], "", goarch, status, start_ns), opts)
        return status
    }
    if command == "ast" {
        if len(args) < 3 {
            return usage_error("ast expects: ast <input.s> [options]")
        }
        opts = parse_common_options(args, 3, opts)
        opts.dump_ast = true
        status := run_ast(args[2], opts)
        finish_command(build_stats(command, args[2], "", goarch, status, start_ns), opts)
        return status
    }
    if command == "test" {
        if len(args) == 3 {
            opts = parse_common_options(args, 3, opts)
            status := run_tests(args[2])
            finish_command(build_stats(command, args[2], "", goarch, status, start_ns), opts)
            return status
        }
        opts = parse_common_options(args, 2, opts)
        status := run_tests("src/cmd/compile/internal/tests/fixtures")
        finish_command(build_stats(command, "src/cmd/compile/internal/tests/fixtures", "", goarch, status, start_ns), opts)
        return status
    }
    return usage_error("unknown command: " + command)
}

func print_usage() () {
    std.io.eprintln("usage: s_modular check <input.s>")
    std.io.eprintln("       s_modular tokens <input.s>")
    std.io.eprintln("       s_modular ast <input.s>")
    std.io.eprintln("       s_modular build <input.s> -o <output> [--nostdlib] [--ssa-margin <n>]")
    std.io.eprintln("       s_modular test [fixtures_root]")
    std.io.eprintln("options: --timing --stats --dump-ast")
}

func default_options() compiler_options {
    compiler_options {
        timing: false,
        stats: false,
        dump_ast: false,
        nostdlib: false,
        ssa_margin_override: "",
    }
}

func parse_common_options(string[] args, int first, compiler_options options) compiler_options {
    i := first
    while i < len(args) {
        if args[i] == "--timing" {
            options.timing = true
        } else if args[i] == "--stats" {
            options.stats = true
        } else if args[i] == "--dump-ast" {
            options.dump_ast = true
        } else {
            std.io.eprintln("compile: unknown option: " + args[i])
        }
        i = i + 1
    }
    return options
}

func parse_build_options(string[] args, int first, compiler_options options) compiler_options {
    i := first
    while i < len(args) {
        if args[i] == "--nostdlib" {
            options.nostdlib = true
        } else if args[i] == "--timing" {
            options.timing = true
        } else if args[i] == "--stats" {
            options.stats = true
        } else if args[i] == "--dump-ast" {
            options.dump_ast = true
        } else if args[i] == "--ssa-margin" {
            if i + 1 >= len(args) {
                std.io.eprintln("compile: --ssa-margin requires a value")
            } else {
                options.ssa_margin_override = args[i + 1]
                i = i + 1
            }
        } else {
            std.io.eprintln("compile: unknown option: " + args[i])
        }
        i = i + 1
    }
    return options
}

func usage_error(string message) int {
    std.io.eprintln("compile: " + message)
    print_usage()
    return 2
}

func run_build(string input, string output, compiler_options options) int {
    if options.dump_ast {
        ast_status := run_ast(input, options)
        if ast_status != 0 {
            return ast_status
        }
    }
    return pipeline_build(input, output, options.ssa_margin_override, options.nostdlib)
}

func run_check(string path, compiler_options options) int {
    source_result := compile.internal.syntax.read_source(path)
    if source_result.is_err() {
        return 1
    }
    source := source_result.unwrap()
    parsed := compile.internal.syntax.parse_source(source)
    if parsed.is_err() {
        return 1
    }
    if options.dump_ast {
        std.io.eprintln("ast ok: " + path)
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

func run_ast(string path, compiler_options options) int {
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

func build_stats(string command, string input, string output, string goarch, int status, int start_ns) compile_stats {
    return compile_stats {
        command: command,
        input: input,
        output: output,
        goarch: goarch,
        exit_status: status,
        elapsed_ns: __runtime_nanotime() - start_ns,
    }
}

func finish_command(compile_stats stats, compiler_options options) () {
    if options.timing {
        std.io.eprintln("compile: timing command=" + stats.command + " elapsed_ns=" + std.conv.int_to_string(stats.elapsed_ns))
    }
    if options.stats {
        std.io.eprintln("compile: stats command=" + stats.command + " input=" + stats.input + " output=" + stats.output + " goarch=" + stats.goarch + " status=" + std.conv.int_to_string(stats.exit_status))
    }
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
    if run_driver_suite() != 0 {
        std.io.eprintln("driver suite failed")
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

extern "intrinsic" func __runtime_nanotime() int
