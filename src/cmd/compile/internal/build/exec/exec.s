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
use compile.internal.semantic.check_text
use compile.internal.syntax.parse_source
use compile.internal.syntax.read_source
use compile.internal.syntax.tokenize

func run(vec[string] options) int {
    if options[0] == "help" {
        return 0
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
