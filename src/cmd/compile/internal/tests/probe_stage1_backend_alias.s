package compile.internal.tests.probe_stage1_backend_alias

import (
    backend_elf64 "compile.internal.backend_elf64"
)

// Test if alias import works
func call_with_alias() int {
    path := "test.s"
    output := "test.o"
    ssa_override := ""
    nostdlib := false
    
    result := backend_elf64.build(path, output, ssa_override, nostdlib)
    return result
}

func main() int {
    return call_with_alias()
}
