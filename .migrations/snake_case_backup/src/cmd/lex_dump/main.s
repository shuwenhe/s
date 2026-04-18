package cmd

use std.env.Args as host_args
use std.result.Result
use std.io.println
use compile.internal.syntax.read_source
use compile.internal.syntax.dump_tokens_text
use compile.internal.syntax.Tokenize

func main() int32 {
    var args = host_args()
    if args.len() < 2 {
        println("usage: lexDump <path>");
        return 1
    }

    var path = args[1]
    switch read_source(path) {
        Result.Err(err) : {
            println("error: " + err.message);
            return 1
        },
        Result.Ok(source) : {
            switch Tokenize(source) {
                Result.Err(err2) : {
                    println("error: " + err2.message);
                    return 1
                },
                Result.Ok(tokens) : {
                    println(dump_tokens_text(tokens));
                    return 0
                },
            }
        },
    }
}
