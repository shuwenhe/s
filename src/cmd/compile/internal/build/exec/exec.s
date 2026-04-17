package compile.internal.build.exec

use compile.internal.build.backend.Build as BuildBinary
use compile.internal.build.backend.Run as RunBinary
use compile.internal.build.emit.Ast as EmitAst
use compile.internal.build.emit.Built as EmitBuilt
use compile.internal.build.emit.CheckOk as EmitCheckOk
use compile.internal.build.emit.Tokens as EmitTokens
use compile.internal.semantic.CheckText
use compile.internal.syntax.ParseSource
use compile.internal.syntax.ReadSource
use compile.internal.syntax.Tokenize
func Run(Vec[string] options) int32 {
    if options[0] == "help" {
        return 0
    }

    var source_result = ReadSource(options[1])
    if source_result.is_err() {
        return 1
    }
    var source = source_result.unwrap()
    if options[0] == "check" {
        var parse_result = ParseSource(source)
        if parse_result.is_err() {
            return 1
        }
        if CheckText(source) != 0 {
            return 1
        }
        EmitCheckOk(options[1]);
        return 0
    }

    if options[0] == "tokens" {
        var tokens_result = Tokenize(source)
        if tokens_result.is_err() {
            return 1
        }
        EmitTokens(tokens_result.unwrap());
        return 0
    }

    if options[0] == "ast" {
        var ast_result = ParseSource(source)
        if ast_result.is_err() {
            return 1
        }
        EmitAst(ast_result.unwrap());
        return 0
    }

    if options[0] == "build" {
        if BuildBinary(options[1], options[2]) == 0 {
            EmitBuilt(options[2]);
            return 0
        }
        return 1
    }

    if options[0] == "run" {
        return RunBinary(options[1])
    }

    return 1
}
