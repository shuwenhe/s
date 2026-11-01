package main
func fallback(int value) int {
    if value > 0 { return value }
    -1
}
func main() int { return fallback(0) + 43 }
