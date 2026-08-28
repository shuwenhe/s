package bootstrap.closure

func identity(string value) string {
    return value
}

func choose(bool condition, string first, string second) string {
    if condition {
        return identity(first)
    }
    return identity(second)
}

func main() {
    string value = choose(true, "hello", "world")
    return len(value) + value[0] - 67
}
