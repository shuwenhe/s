package std.io

func println(string text) () {
    __host_println(text)
}

func eprintln(string text) () {
    __host_eprintln(text)
}

extern "intrinsic" func __host_println(string text) ()

extern "intrinsic" func __host_eprintln(string text) ()
