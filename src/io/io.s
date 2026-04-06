package std.io

func println(String text) -> () {
    __host_println(text)
}

func eprintln(String text) -> () {
    __host_eprintln(text)
}

extern "intrinsic" func __host_println(String text) -> ()

extern "intrinsic" func __host_eprintln(String text) -> ()
