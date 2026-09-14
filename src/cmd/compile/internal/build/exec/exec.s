package compile.internal.build.exec
import (
    "compile.internal.backend_elf64"
    "compile.internal.build.cache"
    "compile.internal.semantic"
    "compile.internal.syntax"
    "compile.internal.tests.test_backend_abi"
    "compile.internal.tests.test_golden"
    "compile.internal.tests.test_mir"
    "compile.internal.tests.test_pipeline_regression"
    "compile.internal.tests.test_semantic"
    "compile.internal.tests.test_ssa"
    "compile.internal.tests.test_typesys"
    "std.env"
    "std.fs"
    "std.io"
    "std.prelude"
)
func run(string[] options) int {
    if options[0] == "help" {
        return 0
    }
    if options[0] == "test" {
        return run_test_command(options
    }
    if options[0] == "mod" {
        return run_mod_command(options
    }
    if is_module_name(options[1]) {
        resolved := compile.internal.backend_elf64.resolve_module_source_path(options[1])
        if resolved.is_none() {
            std.io.eprintln("error: module not found: " + options[1])
            std.io.eprintln("hint: set S_PROJECT_ROOT=<workspace> or S_ROOT=<s-root> so the module can be located")
            return 1
        }
        ignored_set := options.set(1, resolved.unwrap())
    }
    source_result := compile.internal.syntax.read_source(options[1])
    if source_result.is_err() {
        return 1
    }
    source := source_result.unwrap()
    source_key := options[1]
    if options[0] == "check" {
        check_target := "semantic@" + source_key
        check_explain := compile.internal.build.cache.cache_hit_explain_target(options[1], source, "check", check_target)
        if compile.internal.build.cache.cache_hit_target(options[1], source, "check", check_target) {
            ignored := check_explain
            emit_check_ok(options[1]);
            return 0
        }
        parse_result := compile.internal.syntax.parse_source(source)
        if parse_result.is_err() {
            return 1
        }
        if compile.internal.semantic.check_text(source) != 0 {
            return 1
        }
        ignored_cache := compile.internal.build.cache.update_cache_target(options[1], source, "check", check_target)
        emit_check_ok(options[1]);
        return 0
    }
    if options[0] == "tokens" {
        tokens_result := compile.internal.syntax.tokenize(source)
        if tokens_result.is_err() {
            return 1
        }
        emit_tokens(tokens_result.unwrap());
        return 0
    }
    if options[0] == "ast" {
        ast_result := compile.internal.syntax.parse_source(source)
        if ast_result.is_err() {
            return 1
        }
        emit_ast(ast_result.unwrap());
        return 0
    }
    if options[0] == "build" {
        build_target := options[2] + "@" + source_key + "#ssa_margin=" + options[3]
        build_explain := compile.internal.build.cache.cache_hit_explain_target(options[1], source, "build", build_target)
        if compile.internal.build.cache.cache_hit_target(options[1], source, "build", build_target) {
            ignored0 := build_explain
            emit_built(options[2]);
            return 0
        }
        nostdlib := std.prelude.len(options) > 4 && options[4] == "nostdlib"
        if build_binary(options[1], options[2], options[3], nostdlib) == 0 {
            ignored_cache := compile.internal.build.cache.update_cache_target(options[1], source, "build", build_target)
            emit_built(options[2]);
            return 0
        }
        return 1
    }
    if options[0] == "run" {
        nostdlib := std.prelude.len(options) > 4 && options[4] == "nostdlib"
        return run_binary(options[1], options[3], nostdlib
    }
    return 1
}
func run_test_command(string[] options) int {
    fixtures_root := resolve_fixtures_root(options[1])
    semantic_result := compile.internal.tests.test_semantic.run_semantic_suite(fixtures_root)
    if semantic_result != 0 {
        std.io.eprintln("semantic suite failed")
        return semantic_result
    }
    golden_result := compile.internal.tests.test_golden.run_golden_suite(fixtures_root)
    if golden_result != 0 {
        std.io.eprintln("golden suite failed")
        return golden_result
    }
    backend_abi_result := compile.internal.tests.test_backend_abi.run_backend_abi_suite()
    if backend_abi_result != 0 {
        std.io.eprintln("backend abi suite failed")
        return backend_abi_result
    }
    mir_result := compile.internal.tests.test_mir.run_mir_suite()
    if mir_result != 0 {
        std.io.eprintln("mir suite failed")
        return mir_result
    }
    ssa_result := compile.internal.tests.test_ssa.run_ssa_suite()
    if ssa_result != 0 {
        std.io.eprintln("ssa suite failed")
        return ssa_result
    }
    pipeline_result := compile.internal.tests.test_pipeline_regression.run_pipeline_regression_suite()
    if pipeline_result != 0 {
        std.io.eprintln("pipeline regression suite failed")
        return pipeline_result
    }
    typesys_result := compile.internal.tests.test_typesys.run_typesys_suite()
    if typesys_result != 0 {
        std.io.eprintln("typesys suite failed")
        return typesys_result
    }
    std.io.println("test: ok")
    return 0
}
func resolve_fixtures_root(string override) string {
    if override != "" {
        return override
    }
    env_root := std.env.get("s_test_fixtures_root")
    if env_root.is_some() {
        return env_root.unwrap(
    }
    "cmd/compile/internal/tests/fixtures"
}
func run_mod_command(string[] options) int {
    if options[1] == "init" {
        return run_mod_init(options[2]
    }
    if options[1] == "tidy" {
        return run_mod_tidy(
    }
    if options[1] == "index" {
        return run_mod_index(options[2]
    }
    std.io.eprintln("mod command is not supported")
    return 1
}
func run_mod_index(string dir) int {
    if dir == "" {
        std.io.eprintln("mod index failed: directory path required")
        return 1
    }
    std.io.println("mod index: scanning " + dir + "...")
    cmd := string[]()
    cmd = append(cmd, "sh")
    cmd = append(cmd, "-c")
    script := "find " + dir + " -name '*.s' -not -path '*/.*' | while read f; do " +
                 "pkg=$(grep -h '^package ' \"$f\" | head -n1 | sed 's/package
                 "if [ -n \"$pkg\" ]; then printf \"%s\\t%s\\n\" \"$pkg\" \"$f\"; fi; " +
                 "done"
    cmd = append(cmd, script)
    result := run_process_output(cmd)
    if result.is_err() {
        std.io.eprintln("mod index failed: " + result.unwrap_err().message)
        return 1
    }
    index_content := result.unwrap()
    write_res := std.fs.write_text_file("scripts/s-package-index.tsv", index_content)
    if write_res.is_err() {
        std.io.eprintln("failed to save index: " + write_res.unwrap_err().message)
        return 1
    }
    std.io.println("mod index: generated scripts/s-package-index.tsv")
    0
}
func run_mod_init(string module_name) int {
    if !is_valid_module_name(module_name) {
        std.io.eprintln("mod init failed: invalid module name")
        return 1
    }
    existing := std.fs.read_to_string("s.mod")
    if existing.is_ok() {
        std.io.eprintln("mod init failed: s.mod already exists")
        return 1
    }
    content := "[package]\n"
        + "name = \"" + module_name + "\"\n"
        + "version = \"0.1.0\"\n"
        + "edition = \"2026\"\n\n"
        + "[dependencies]\n"
    write_result := std.fs.write_text_file("s.mod", content)
    if write_result.is_err() {
        std.io.eprintln("mod init failed: " + write_result.unwrap_err().message)
        return 1
    }
    std.io.println("mod init: created s.mod")
    return 0
}
func run_mod_tidy() int {
    read_result := std.fs.read_to_string("s.mod")
    if read_result.is_err() {
        std.io.eprintln("mod tidy failed: s.mod not found")
        return 1
    }
    std.io.println("mod tidy: ok")
    return 0
}
func is_valid_module_name(string name) bool {
    if name == "" {
        return false
    }
    i := 0
    for i < std.prelude.len(name) {
        ch := std.prelude.char_at(name, i)
        if ch == " " || ch == "\t" || ch == "\r" || ch == "\n" {
            return false
        }
        i = i + 1
    }
    true
}
func is_module_name(string path) bool {
    if path == "" {
        return false
    }
    has_dot := false
    i := 0
    for i < std.prelude.len(path) {
        ch := std.prelude.char_at(path, i)
        if ch == "/" {
            return false
        }
        if ch == "." {
            has_dot = true
        }
        i = i + 1
    }
    if !has_dot {
        return false
    }
    if std.prelude.len(path) >= 2 {
        if std.prelude.char_at(path, std.prelude.len(path) - 2) == "." && std.prelude.char_at(path, std.prelude.len(path) - 1) == "s" {
            return false
        }
    }
    true
