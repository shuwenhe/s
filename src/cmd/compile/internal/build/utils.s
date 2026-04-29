package compile.internal.build.utils

use s.source_file
use s.token

use compile.internal.build.parse.parse_options as parse_options_impl
use compile.internal.build.parse.usage as usage_impl
use compile.internal.build.emit.check_ok as emit_check_ok_impl
use compile.internal.build.emit.tokens as emit_tokens_impl
use compile.internal.build.emit.ast as emit_ast_impl
use compile.internal.build.emit.built as emit_built_impl
use compile.internal.build.report.error as report_error_impl
use compile.internal.build.report.usage as report_usage_impl
use compile.internal.build.backend.build as backend_build_impl
use compile.internal.build.backend.run as backend_run_impl
use compile.internal.build.frontend.load as frontend_load_impl

func parse_options(vec[string] args)  vec[string] {
    return parse_options_impl(args)
}

func usage() string {
    return usage_impl()
}

func emit_check_ok(string path) () {
    emit_check_ok_impl(path)
}

func emit_tokens(vec[token] tokens) () {
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

func build(string path, string output, string ssa_margin) int {
    return backend_build_impl(path, output, ssa_margin)
}

func run(string path, string ssa_margin) int {
    return backend_run_impl(path, ssa_margin)
}

func load_frontend(string path) string {
    return frontend_load_impl(path)
}
