package compile.internal.tests.probe_stage1_backend_call

import (
    "compile.internal.backend_elf64"
)

// Direct call to test if seed can handle qualified symbol calls
func call_backend_build() int {
    path := "test.s"
    output := "test.o"
    ssa_override := ""
    nostdlib := false
    
    result := compile.internal.backend_elf64.build(path, output, ssa_override, nostdlib)
    return result
}

func main() int {
    return call_backend_build()
}
