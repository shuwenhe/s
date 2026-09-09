package main

struct Resource {
    id int
}

struct Quad {
    a Resource
    b Resource
    c Resource
    d Resource
}

func main() int {
    p := Quad(
        Resource(1),
        Resource(2),
        Resource(3),
        Resource(4)
    )
    
    x := p.c        // ← p.c MOVED
    return x.id
}
