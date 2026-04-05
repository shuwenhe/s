package std.io

func println(text: String) -> () {
    __host_println(text)
}

func eprintln(text: String) -> () {
    __host_eprintln(text)
}

extern "intrinsic" func __host_println(text: String) -> ()

extern "intrinsic" func __host_eprintln(text: String) -> ()
