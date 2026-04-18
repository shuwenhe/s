package compile.internal.build.emit

use s.source_file
use s.token
use s.dump_source_file
use s.dump_tokens
use std.io.println
use std.vec.vec

func check_ok(string path) () {
    println("ok: " + path)
}

func tokens(vec[token] tokens) () {
    println(dump_tokens(tokens))
}

func ast(source_file ast) () {
    println(dump_source_file(ast))
}

func built(string output) () {
    println("built: " + output)
}
