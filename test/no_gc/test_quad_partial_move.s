package test

// P0A Gate Test: 4字段 Quad 第三字段 partial move

struct Resource {
    value box
}

struct Quad {
    a Resource
    b Resource
    c Resource
    d Resource
}

func main() {
    p := Quad(
        Resource(box(10)),
        Resource(box(20)),
        Resource(box(30)),
        Resource(box(40))
    )

    // *** 关键：partial move 第三字段 (field index 2) ***
    x := p.c

    println("got third field")
}
