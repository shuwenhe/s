package main

func main() int {
    p := pair(box(1), box(2))  // create a pair with two owned box fields
    x := p.right              // ← access right field (which is owned box)
    return 0
}
