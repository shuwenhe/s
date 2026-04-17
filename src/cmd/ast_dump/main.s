package cmd

use std.env.Args as host_args
use std.io.println
use std.result.Result
use compile.internal.syntax.DumpSourceText
use compile.internal.syntax.ParseSource
use compile.internal.syntax.ReadSource

func main() int32 {
    var args = host_args()
    if args.len() < 2 {
        println("usage: astDump <path>");
        return 1
    }

    var path = args[1]
    switch ReadSource(path) {
        Result.Err(err) : {
            println("error: " + err.message);
            return 1
        },
        Result.Ok(source) : {
            switch ParseSource(source) {
                Result.Err(err2) : {
                    println("error: " + err2.message);
                    return 1
                },
                Result.Ok(ast) : {
                    println(DumpSourceText(ast));
                    return 0
                },
            }
        },
    }
}
