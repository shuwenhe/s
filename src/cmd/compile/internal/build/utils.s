package compile.internal.build.utils
import (
    "s"
)
func parse_options(string[] args)  string[] {
    return parse_options_impl(args
}

func usage() string {
    return usage_impl(
}

func emit_check_ok(string path) () {
    emit_check_ok_impl(path)
}

func emit_tokens(token[] tokens) () {
    emit_tokens_impl(tokens)
}

func emit_ast(source_file ast) () {
    emit_ast_impl(ast)
}

func emit_built(string output) () {
    emit_built_impl(output)
}

func report_error(string message) () {
    report_error_impl(message)
}

func report_usage(string text) () {
    report_usage_impl(text)
}

func build(string path, string output, string ssa_margin, bool nostdlib) int {
    return backend_build_impl(path, output, ssa_margin, nostdlib
}

func run(string path, string ssa_margin, bool nostdlib) int {
    return backend_run_impl(path, ssa_margin, nostdlib
}

func load_frontend(string path) string {
    return frontend_load_impl(path
}
