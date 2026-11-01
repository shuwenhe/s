package main
struct value { int number }
func observe(value first, int second) int {
    if first.number != 21 { return 1 }
    if second != 99 { return 2 }
    return 42
}
func main() int {
    original := value { number: 21 }
    return observe(original, original.number = 99)
}
