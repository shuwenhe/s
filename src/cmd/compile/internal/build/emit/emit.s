package compile.internal.build.emit

use s.SourceFile
use s.Token
use s.dump_source_file
use s.dump_tokens
use std.io.println
use std.vec.Vec

func CheckOk(string path) () {
    println("ok: " + path)
}

func Tokens(Vec[Token] tokens) () {
    println(dump_tokens(tokens))
}

func Ast(SourceFile ast) () {
    println(dump_source_file(ast))
}

func Built(string output) () {
    println("built: " + output)
}
