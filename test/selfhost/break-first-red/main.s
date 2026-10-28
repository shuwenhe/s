package main
func main() int {
    i := 0
    for i < 10 {
        i = i + 1
        if i == 2 { break }
    }
    return i + 40
}
