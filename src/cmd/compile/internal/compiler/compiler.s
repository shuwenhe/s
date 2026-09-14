package compile.internal.compiler
import (
    "std"
)
func main(string[] args) int {
    buildcfg_err := buildcfg_check()
    if buildcfg_err != "" {
        return 2
    }
    arch_err := arch_dispatch_init(buildcfg_goarch())
    if arch_err != "" {
        return 2
    }
    return build_main(args)
}
func run_cli(string[] args) int {
    main(args)
