package test.simple_quad

struct Triple {
    box a
    box b
    box c
}

func main() {
    t := Triple{box(1), box(2), box(3)}
    x := t.c
    println(*x)
}
