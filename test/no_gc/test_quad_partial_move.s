package test


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


    x := p.c

    println("got third field")
}
