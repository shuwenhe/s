package main

struct Pair {
    left: *box int
    right: *box int
}

func main() int {
    p := pair(box(1), box(2))
    x := p.left
    return 0
}
