package compile.internal.build.exec

use compile.internal.build.utils.build as build_binary
use compile.internal.build.utils.run as run_binary
use compile.internal.build.utils.emit_ast as emit_ast
use compile.internal.build.utils.emit_built as emit_built
use compile.internal.build.utils.emit_check_ok as emit_check_ok
use compile.internal.build.utils.emit_tokens as emit_tokens
use compile.internal.build.cache.cache_hit_target
use compile.internal.build.cache.cache_hit_explain_target
use compile.internal.build.cache.update_cache_target
use compile.internal.tests.test_golden.run_golden_suite
use compile.internal.tests.test_backend_abi.run_backend_abi_suite
use compile.internal.tests.test_mir.run_mir_suite
use compile.internal.tests.test_ssa.run_ssa_suite
use compile.internal.tests.test_pipeline_regression.run_pipeline_regression_suite
use compile.internal.tests.test_typesys.run_typesys_suite
use compile.internal.tests.test_semantic.run_semantic_suite
use compile.internal.semantic.check_text
use compile.internal.syntax.parse_source
use compile.internal.syntax.read_source
use compile.internal.syntax.tokenize
use std.env.get
use std.fs.read_to_string
use std.fs.write_text_file
use std.io.eprintln
use std.io.println
use std.prelude.char_at
use std.prelude.len

func run(vec[string] options) int {
    if options[0] == "help" {
        return 0
    }

    if options[0] == "test" {
        return run_test_command(options)
    }

    if options[0] == "mod" {
        return run_mod_command(options)
    }

    let source_result = read_source(options[1])
    if source_result.is_err() {
        return 1
    }
    let source = source_result.unwrap()
    let source_key = options[1]
    if options[0] == "check" {
        let check_target = "semantic@" + source_key
        let check_explain = cache_hit_explain_target(options[1], source, "check", check_target)
        if cache_hit_target(options[1], source, "check", check_target) {
            let ignored = check_explain
            emit_check_ok(options[1]);
            return 0
        }
        let parse_result = parse_source(source)
        if parse_result.is_err() {
            return 1
        }
        if check_text(source) != 0 {
            return 1
        }
        let ignored_cache = update_cache_target(options[1], source, "check", check_target)
        emit_check_ok(options[1]);
        return 0
    }

    if options[0] == "tokens" {
        let tokens_result = tokenize(source)
        if tokens_result.is_err() {
            return 1
        }
        emit_tokens(tokens_result.unwrap());
        return 0
    }

    if options[0] == "ast" {
        let ast_result = parse_source(source)
        if ast_result.is_err() {
            return 1
        }
        emit_ast(ast_result.unwrap());
        return 0
    }

    if options[0] == "build" {
        let build_target = options[2] + "@" + source_key + "#ssa_margin=" + options[3]
        let build_explain = cache_hit_explain_target(options[1], source, "build", build_target)
        if cache_hit_target(options[1], source, "build", build_target) {
            let ignored0 = build_explain
            emit_built(options[2]);
            return 0
        }
        if build_binary(options[1], options[2], options[3]) == 0 {
            let ignored_cache = update_cache_target(options[1], source, "build", build_target)
            emit_built(options[2]);
            return 0
        }
        return 1
    }

    if options[0] == "run" {
        return run_binary(options[1], options[3])
    }

    return 1
}

func run_test_command(vec[string] options) int {
    let fixtures_root = resolve_fixtures_root(options[1])

    let semantic_result = run_semantic_suite(fixtures_root)
    if semantic_result != 0 {
        eprintln("semantic suite failed")
        return semantic_result
    }

    let golden_result = run_golden_suite(fixtures_root)
    if golden_result != 0 {
        eprintln("golden suite failed")
        return golden_result
    }

    let backend_abi_result = run_backend_abi_suite()
    if backend_abi_result != 0 {
        eprintln("backend abi suite failed")
        return backend_abi_result
    }

    let mir_result = run_mir_suite()
    if mir_result != 0 {
        eprintln("mir suite failed")
        return mir_result
    }

    let ssa_result = run_ssa_suite()
    if ssa_result != 0 {
        eprintln("ssa suite failed")
        return ssa_result
    }

    let pipeline_result = run_pipeline_regression_suite()
    if pipeline_result != 0 {
        eprintln("pipeline regression suite failed")
        return pipeline_result
    }

    let typesys_result = run_typesys_suite()
    if typesys_result != 0 {
        eprintln("typesys suite failed")
        return typesys_result
    }

    println("test: ok")
    return 0
}

func resolve_fixtures_root(string override) string {
    if override != "" {
        return override
    }
    let env_root = get("s_test_fixtures_root")
    if env_root.is_some() {
        return env_root.unwrap()
    }
    "cmd/compile/internal/tests/fixtures"
}

func run_mod_command(vec[string] options) int {
    if options[1] == "init" {
        return run_mod_init(options[2])
    }
    if options[1] == "tidy" {
        return run_mod_tidy()
    }
    eprintln("mod command is not supported")
    return 1
}

func run_mod_init(string module_name) int {
    if !is_valid_module_name(module_name) {
        eprintln("mod init failed: invalid module name")
        return 1
    }

    let existing = read_to_string("s.mod")
    if existing.is_ok() {
        eprintln("mod init failed: s.mod already exists")
        return 1
    }

    let content = "[package]\n"
        + "name = \"" + module_name + "\"\n"
        + "version = \"0.1.0\"\n"
        + "edition = \"2026\"\n\n"
        + "[dependencies]\n"

    let write_result = write_text_file("s.mod", content)
    if write_result.is_err() {
        eprintln("mod init failed: " + write_result.unwrap_err().message)
        return 1
    }

    println("mod init: created s.mod")
    return 0
}

func run_mod_tidy() int {
    let read_result = read_to_string("s.mod")
    if read_result.is_err() {
        eprintln("mod tidy failed: s.mod not found")
        return 1
    }

    println("mod tidy: ok")
    return 0
}

func is_valid_module_name(string name) bool {
    if name == "" {
        return false
    }
    let i = 0
    while i < len(name) {
        let ch = char_at(name, i)
        if ch == " " || ch == "\t" || ch == "\r" || ch == "\n" {
            return false
        }
        i = i + 1
    }
    true
}
