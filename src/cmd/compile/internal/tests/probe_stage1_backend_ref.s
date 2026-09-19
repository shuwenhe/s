package compile.internal.tests.probe_stage1_backend_ref

import (
    "compile.internal.backend_elf64"
)

// Reference the build function without calling it
// to test symbol resolution at seed level
func get_build_func() func {
    return compile.internal.backend_elf64.build
}

func main() int {
    return 0
}
