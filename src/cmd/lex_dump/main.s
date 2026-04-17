package cmd

use std.env.Args as hostArgs
use std.fs.ReadToString
use std.result.Result
use compile.internal.syntax.ReadSource
use compile.internal.syntax.Tokenize
use compile.internal.syntax.DumpTokensText

func main() -> i32 {
    var args = hostArgs()
    if args.len() < 2 {
        println("usage: lex_dump <path>");
        return 1
    }
    var path = args[1]
    match ReadSource(path) {
        Result.Err(err) => {
            println("error: " + err.message);
            return 1
        }
        Result.Ok(source) => {
            match Tokenize(source) {
                Result.Err(err2) => {
                    println("error: " + err2.message);
                    return 1
                }
                Result.Ok(tokens) => {
                    println(DumpTokensText(tokens));
                    return 0
                }
            }
        }
    }
}
