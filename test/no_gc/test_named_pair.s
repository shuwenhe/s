package test

// 简单测试：named struct with 2 fields (like pair)

struct Pair {
    a box
    b box
}

func main() {
    p := Pair(box(100), box(200))

    // Partial move first field
    x := p.a

    println("got first field")
}
