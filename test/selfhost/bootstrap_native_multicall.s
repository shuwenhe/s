package main
func first() int {
    return 5 * 2
}

func second() int {
    return first() * 2
}

func main() {
    return second() * 2 + 2
}
