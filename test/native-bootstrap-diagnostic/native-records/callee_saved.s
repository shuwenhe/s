package main
func g(int x) int { return x }
func f() int { return g(1) }
func main() int {
    a := 20
    b := 22
    ignored := f()
    return a + b
}
