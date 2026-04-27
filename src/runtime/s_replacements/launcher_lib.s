// S 实现：launcher_lib.c
// 提供 launcher 进程调用

fn launcher_run_argv(args: [string]): int {
    return process_runner_run_argv(args)
}

fn launcher_run_shell(command: string): int {
    return process_runner_run_shell(command)
}
