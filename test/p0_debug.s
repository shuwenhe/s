package main

struct Quad {
    a: int
    b: int
    c: int
    d: int
}

func main() int {
    p := Quad(1, 2, 3, 4)
    x := p.c
    return x
}
