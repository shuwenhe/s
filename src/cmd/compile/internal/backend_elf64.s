package compile.internal.backend_elf64

use compile.internal.build.backend.Build as BuildBinary

func Build(String path, String output) -> i32 {
    BuildBinary(path, output)
}

func buildExecutable(String path, String output) -> i32 {
    BuildBinary(path, output)
}
