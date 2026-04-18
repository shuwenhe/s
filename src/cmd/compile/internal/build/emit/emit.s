package compile.internal.build.emit

use s.source_file
use s.Token
use s.dump_source_file
use s.dump_tokens
use std.io.println
use std.vec.Vec

func check_ok(string path) () {
    println("ok: " + path)
}

func Tokens(Vec[Token] tokens) () {
    println(dump_tokens(tokens))
}

func Ast(source_file ast) () {
    println(dump_source_file(ast))
}

func Built(string output) () {
    println("built: " + output)
}
