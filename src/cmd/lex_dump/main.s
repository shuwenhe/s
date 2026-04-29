package cmd

use std.env.args as host_args
use std.result.result
use std.io.println
use compile.internal.syntax.read_source
use compile.internal.syntax.dump_tokens_text
use compile.internal.syntax.tokenize

func main() int {
    let args = host_args()
    if args.len() < 2 {
        println("usage: lex_dump <path>");
        return 1
    }

    let path = args[1]
    switch read_source(path) {
        result.err(err) : {
            println("error: " + err.message);
            return 1
        },
        result.ok(source) : {
            switch tokenize(source) {
                result.err(err2) : {
                    println("error: " + err2.message);
                    return 1
                },
                result.ok(tokens) : {
                    println(dump_tokens_text(tokens));
                    return 0
                },
            }
        },
    }
}
