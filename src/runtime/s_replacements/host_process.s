// S 实现：host_process.py
// 提供进程运行功能，直接调用 S 运行时的 process_runner_run_argv

fn run_argv(argv: [string]): int {
    return process_runner_run_argv(argv)
}
