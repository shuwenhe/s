package compile.internal.backend
import (
    "compile.internal.backend_elf64"
)
func build(string input, string output) int {
    compile.internal.backend_elf64.build(input, output)
}
