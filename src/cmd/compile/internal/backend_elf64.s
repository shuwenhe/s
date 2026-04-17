package compile.internal.backend_elf64

use compile.internal.build.backend.Build as BuildBinary

func Build(string path, string output) int32 {
    BuildBinary(path, output)
}

func buildExecutable(string path, string output) int32 {
    BuildBinary(path, output)
}
