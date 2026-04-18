package compile.internal.main

use compile.internal.compiler.Main as compiler_main

func main(Vec[string] args) int32 {
    return compiler_main(args)
}

func main() int32 {
    0
}
