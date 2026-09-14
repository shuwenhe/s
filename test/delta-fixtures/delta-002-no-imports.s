package cmd

func main() int {
    args := std.env.args()
    if len(args) == 2 && args[1] == "--help" {
        print_usage()
        return 0
    }
    if len(args) < 2 {
        print_usage()
        return 2
    }
    buildcfg_err := init_buildcfg(args[1])
    if buildcfg_err != nil {
        fmt_fprintln(std.io.stderr(), "error: " + buildcfg_err.string())
        return 2
    }
    result := cmd_compile(args[1:])
    return result
}

func print_usage() {
}

func init_buildcfg(root string) error {
    return nil
}

func cmd_compile(args []string) int {
    return 0
}
