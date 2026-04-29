
fn wait_for_child(pid: int): int {
    let status = os.waitpid(pid)
    if status.type == "exit" {
        return status.code
    }
    if status.type == "signal" {
        return 128 + status.signal
    }
    return 1
}

fn process_runner_run_argv(argv: [string]): int {
    if argv.len() == 0 || argv[0] == nil {
        return 127
    }
    let pid = os.fork()
    if pid < 0 {
        return 127
    }
    if pid == 0 {
        os.execvp(argv[0], argv)
        os.exit(127)
    }
    return wait_for_child(pid)
}

fn process_runner_run_shell(command: string): int {
    if command == nil || command == "" {
        return 127
    }
    let pid = os.fork()
    if pid < 0 {
        return 127
    }
    if pid == 0 {
        os.execl("/bin/sh", ["sh", "-c", command])
        os.exit(127)
    }
    return wait_for_child(pid)
}
