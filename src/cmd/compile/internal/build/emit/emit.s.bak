package compile.internal.build.emit

use s.SourceFile
use s.Token
use s.dumpSourceFile
use s.dumpTokens
use std.io.println
use std.vec.Vec

func CheckOk(string path) () {
    println("ok: " + path)
}

func Tokens(Vec[Token] tokens) () {
    println(dumpTokens(tokens))
}

func Ast(SourceFile ast) () {
    println(dumpSourceFile(ast))
}

func Built(string output) () {
    println("built: " + output)
}
