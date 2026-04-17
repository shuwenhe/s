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
use compile.internal.build.parse.CompileOptions

func Run(Vec[string] options) int32 {
    if options[0] == "help" {
        return 0
    }

    var sourceResult = ReadSource(options[1])
    if sourceResult.is_err() {
        return 1
    }
    var source = sourceResult.unwrap()
    if options[0] == "check" {
        var parseResult = ParseSource(source)
        if parseResult.is_err() {
            return 1
        }
        if CheckText(source) != 0 {
            return 1
        }
        EmitCheckOk(options[1]);
        return 0
    }

    if options[0] == "tokens" {
        var tokensResult = Tokenize(source)
        if tokensResult.is_err() {
            return 1
        }
        EmitTokens(tokensResult.unwrap());
        return 0
    }

    if options[0] == "ast" {
        var astResult = ParseSource(source)
        if astResult.is_err() {
            return 1
        }
        EmitAst(astResult.unwrap());
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
