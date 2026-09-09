package test.minimal

struct Pair {
    box left
    box right
}

func main() {
    p := Pair{box(1), box(2)}
    x := p.right
    println(*x)
}
