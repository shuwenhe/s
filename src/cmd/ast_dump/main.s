package cmd

use std.env.Args as host_args
use std.io.println
use std.result.Result
use compile.internal.syntax.dump_source_text
use compile.internal.syntax.parse_source
use compile.internal.syntax.read_source

func main() int32 {
    var args = host_args()
    if args.len() < 2 {
        println("usage: astDump <path>");
        return 1
    }

    var path = args[1]
    switch read_source(path) {
        Result.Err(err) : {
            println("error: " + err.message);
            return 1
        },
        Result.Ok(source) : {
            switch parse_source(source) {
                Result.Err(err2) : {
                    println("error: " + err2.message);
                    return 1
                },
                Result.Ok(ast) : {
                    println(dump_source_text(ast));
                    return 0
                },
            }
        },
    }
}
