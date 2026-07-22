
func launcher_run_argv(args: [string]): int {
    return process_runner_run_argv(args)
}

func launcher_run_shell(command: string): int {
    return process_runner_run_shell(command)
}
