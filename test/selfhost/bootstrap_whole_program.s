package bootstrap.closure

func leaf(string value) int {
    return len(value)
}

func middle(bool use_first, string first, string second) int {
    string selected = choose(use_first, first, second)
    return leaf(selected)
}

func choose(bool condition, string first, string second) string {
    if condition {
        return first
    }
    return second
}

func main() {
    return middle(true, "hello", "x") + 37
}
