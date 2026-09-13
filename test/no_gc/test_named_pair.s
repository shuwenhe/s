package test

struct Pair {
    a box
    b box
}

func main() {
    p := Pair(box(100), box(200))

    x := p.a

    println("got first field")
}
