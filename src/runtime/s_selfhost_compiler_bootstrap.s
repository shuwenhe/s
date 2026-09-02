package runtime
use compile.internal.compiler.main as compiler_main
use std.env as env
use std.io  as io
use std.slices
use std.result.result
const bootstrap_version = "0.2.0"
const bootstrap_stage   = "stage1"
const cmd_unknown = 0
const cmd_check   = 1
const cmd_build   = 2
const cmd_run     = 3
const cmd_lex     = 4
const cmd_ast     = 5
const cmd_version = 6
const cmd_help    = 7
func main() {
    runtime_init()
    gc_disable()
    args := env.args()
    if len(args) < 2 {
        print_usage()
        return 1
    }
    cmd_str := args.get(1).unwrap_or("")
    cmd     := parse_command(cmd_str)
    switch cmd {
        cmd_version : {
            io.println("s compiler " + bootstrap_version + " (" + bootstrap_stage + ")")
            return 0
        },
        cmd_help : {
            print_usage()
            return 0
        },
        cmd_unknown : {
            compiler_main(args)
        },
        _ : {
            compiler_main(args)
        },
    }
    0
}

func parse_command(string s) int {
    if s == "check"   { return cmd_check   }
    if s == "build"   { return cmd_build   }
    if s == "run"     { return cmd_run     }
    if s == "lex"     { return cmd_lex     }
    if s == "ast"     { return cmd_ast     }
    if s == "version" { return cmd_version }
    if s == "--version" { return cmd_version }
    if s == "help"    { return cmd_help    }
    if s == "--help"  { return cmd_help    }
    if s == "-h"      { return cmd_help    }
    cmd_unknown
}

func print_usage() () {
    io.println("s compiler " + bootstrap_version)
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
