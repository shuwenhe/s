package runtime

use compile.internal.compiler.main as compiler_main
use std.env as env
use std.io  as io
use std.vec.vec
use std.result.result

const BOOTSTRAP_VERSION = "0.2.0"
const BOOTSTRAP_STAGE   = "stage1"

const CMD_UNKNOWN = 0
const CMD_CHECK   = 1
const CMD_BUILD   = 2
const CMD_RUN     = 3
const CMD_LEX     = 4
const CMD_AST     = 5
const CMD_VERSION = 6
const CMD_HELP    = 7

func main() int {
    runtime_init()
    gc_disable()

    let args = env.args()

    if args.len() < 2 {
        print_usage()
        return 1
    }

    let cmd_str = args.get(1).unwrap_or("")
    let cmd     = parse_command(cmd_str)

    switch cmd {
        CMD_VERSION : {
            io.println("s compiler " + BOOTSTRAP_VERSION + " (" + BOOTSTRAP_STAGE + ")")
            return 0
        },
        CMD_HELP : {
            print_usage()
            return 0
        },
        CMD_UNKNOWN : {
            compiler_main(args)
        },
        _ : {
            compiler_main(args)
        },
    }

    0
}

func parse_command(string s) int {
    if s == "check"   { return CMD_CHECK   }
    if s == "build"   { return CMD_BUILD   }
    if s == "run"     { return CMD_RUN     }
    if s == "lex"     { return CMD_LEX     }
    if s == "ast"     { return CMD_AST     }
    if s == "version" { return CMD_VERSION }
    if s == "--version" { return CMD_VERSION }
    if s == "help"    { return CMD_HELP    }
    if s == "--help"  { return CMD_HELP    }
    if s == "-h"      { return CMD_HELP    }
    CMD_UNKNOWN
}

func print_usage() () {
    io.println("s compiler " + BOOTSTRAP_VERSION)
    io.println("")
    io.println("Usage:")
    io.println("  s check  <path>            Check syntax and types")
    io.println("  s build  <path> -o <out>   Compile to native binary")
    io.println("  s run    <path> [args...]   Compile and run")
    io.println("  s lex    <path>            Dump token stream")
    io.println("  s ast    <path>            Dump AST")
    io.println("  s version                  Print version")
    io.println("")
    io.println("Options:")
    io.println("  --dump-tokens   Print lexer output")
    io.println("  --dump-ast      Print parser output")
    io.println("  --verbose       Verbose compilation output")
}
