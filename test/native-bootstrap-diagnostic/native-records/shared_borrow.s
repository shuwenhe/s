package main
struct cell { int number }
func read(cell& value) int { return value.number }
func same(cell& first, cell& second) bool { return first == second }
func main() int {
    original := cell { number: 21 }
    if same(original, original) { return read(original) + read(original) }
    return 1
}
