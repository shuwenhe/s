package compile.internal.backend

use compile.internal.backend_elf64.build as build_elf64

func build(string input, string output) int {
    build_elf64(input, output)
}
