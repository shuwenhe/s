package std.io
func print(string text) () {
    println(text)
}

func println(string text) () {
    __host_println(text)
}

func eprintln(string text) () {
    __host_eprintln(text)
}
