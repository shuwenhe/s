// ============================================================
// s_selfhost_compiler_bootstrap.s
// S 编译器自举入口
//
// 职责：
//   1. 初始化运行时（GC、调度器、信号处理）
//   2. 解析命令行参数，分发到编译器子命令
//   3. 处理 check / build / run / lex / ast 等命令
//   4. 提供自举阶段的错误报告
//
// 自举路径（参见 doc/bootstrap_flow.md）：
//   stage0（Python 宿主）→ 编译本文件 →
//   stage1（s_compiler_stage1）→ 编译完整编译器 →
//   final（bin/s_arm64）
// ============================================================
package runtime

use compile.internal.compiler.main as compiler_main
use std.env as env
use std.io  as io
use std.vec.vec
use std.result.result

// ─── 自举版本标识 ─────────────────────────────────────────────
const BOOTSTRAP_VERSION = "0.2.0"
const BOOTSTRAP_STAGE   = "stage1"

// ─── 命令枚举 ────────────────────────────────────────────────
const CMD_UNKNOWN = 0
const CMD_CHECK   = 1
const CMD_BUILD   = 2
const CMD_RUN     = 3
const CMD_LEX     = 4
const CMD_AST     = 5
const CMD_VERSION = 6
const CMD_HELP    = 7

// ─── 主入口 ───────────────────────────────────────────────────
func main() int {
    // 1. 运行时初始化
    runtime_init()
    gc_disable()   // 自举阶段关闭 GC 以减少变量

    // 2. 读取参数
    let args = env.args()

    // 3. 参数不足时打印用法
    if args.len() < 2 {
        print_usage()
        return 1
    }

    // 4. 解析第一个参数作为子命令
    let cmd_str = args.get(1).unwrap_or("")
    let cmd     = parse_command(cmd_str)

    // 5. 分发到编译器主入口或内置处理
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
            // 将所有参数转发给编译器主入口
            compiler_main(args)
        },
        _ : {
            // check / build / run / lex / ast 全部转发给编译器
            compiler_main(args)
        },
    }

    0
}

// ─── 命令字符串解析 ───────────────────────────────────────────
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

// ─── 用法说明 ─────────────────────────────────────────────────
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
