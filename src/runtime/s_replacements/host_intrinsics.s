// S 实现：host_intrinsics.c
// 提供命令行参数、环境变量、打印等功能

var g_args: [string] = []

fn host_intrinsics_init(args: [string]) {
    g_args = args[1:]
}

fn host_intrinsics_argc(): int {
    return g_args.len()
}

fn host_intrinsics_argv(index: int): string {
    if index < 0 || index >= g_args.len() {
        return nil
    }
    return g_args[index]
}

fn host_intrinsics_get_env(key: string): string {
    return os.getenv(key)
}

fn host_intrinsics_println(text: string) {
    print(text)
}

fn host_intrinsics_eprintln(text: string) {
    eprint(text)
}
