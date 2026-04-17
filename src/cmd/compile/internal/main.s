package compile.internal.main

use compile.internal.gc.Main as gcMain

func Main(Vec[String] args) -> i32 {
    gcMain(args)
}

func main() -> i32 {
    0
}
