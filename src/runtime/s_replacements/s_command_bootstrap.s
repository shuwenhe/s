
func try_exec_if_present(path: string, args: [string]) {
    if path != nil && path != "" && os.is_executable(path) {
        os.execv(path, args)
    }
}

func main(args: [string]): int {
    try_exec_if_present(os.getenv("S_SELFHOSTED"), args)
    try_exec_if_present(os.getenv("s_selfhosted_runner"), args)
    try_exec_if_present("/app/s/bin/s_arm64", args)
    eprint("s command launcher")
    return 127
}
