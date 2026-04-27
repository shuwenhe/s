// S 实现：s_command_bootstrap.c
// 提供 s 命令入口，尝试 exec 多个路径

fn try_exec_if_present(path: string, args: [string]) {
    if path != nil && path != "" && os.is_executable(path) {
        os.execv(path, args)
    }
}

fn main(args: [string]): int {
    try_exec_if_present(os.getenv("S_SELFHOSTED"), args)
    try_exec_if_present(os.getenv("s_selfhosted_runner"), args)
    try_exec_if_present("/app/s/bin/s-selfhosted", args)
    eprint("s command launcher")
    return 127
}
