package compile.internal.build.exec

use compile.internal.build.backend.build as build_binary
use compile.internal.build.backend.run as run_binary
use compile.internal.build.emit.ast as emit_ast
use compile.internal.build.emit.built as emit_built
use compile.internal.build.emit.check_ok as emit_check_ok
use compile.internal.build.emit.tokens as emit_tokens
use compile.internal.semantic.check_text
use compile.internal.syntax.parse_source
use compile.internal.syntax.read_source
use compile.internal.syntax.tokenize
use compile.internal.build.parse.compile_options

func run(vec[string] options) int32 {
    if options[0] == "help" {
        return 0
    }

    var source_result = read_source(options[1])
    if source_result.is_err() {
        return 1
    }
    var source = source_result.unwrap()
    if options[0] == "check" {
        var parse_result = parse_source(source)
        if parse_result.is_err() {
            return 1
        }
        if check_text(source) != 0 {
            return 1
        }
        emit_check_ok(options[1]);
        return 0
    }

    if options[0] == "tokens" {
        var tokens_result = tokenize(source)
        if tokens_result.is_err() {
            return 1
        }
        emit_tokens(tokens_result.unwrap());
        return 0
    }

    if options[0] == "ast" {
        var ast_result = parse_source(source)
        if ast_result.is_err() {
            return 1
        }
        emit_ast(ast_result.unwrap());
        return 0
    }

    if options[0] == "build" {
        if build_binary(options[1], options[2]) == 0 {
            emit_built(options[2]);
            return 0
        }
        return 1
    }

    if options[0] == "run" {
        return run_binary(options[1])
    }

    return 1
}
