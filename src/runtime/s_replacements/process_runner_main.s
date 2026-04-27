// S 实现：process_runner_main.c
// 提供进程运行入口

fn usage(): int {
    eprint("usage: process_runner run-argv <program> [arg ...] | run-shell <command>")
    return 1
}

fn main(args: [string]): int {
    if args.len() < 2 {
        return usage()
    }
    if args[1] == "run-argv" {
        if args.len() < 3 {
            return usage()
        }
        return process_runner_run_argv(args[2:])
    }
    if args[1] == "run-shell" {
        if args.len() != 3 {
            return usage()
        }
        return process_runner_run_shell(args[2])
    }
    return usage()
}
