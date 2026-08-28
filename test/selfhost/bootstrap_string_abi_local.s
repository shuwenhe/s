package bootstrap.closure

func identity(string value) string {
    return value
}

func main() {
    string first = identity("hello")
    string value = first
    return len(value) + value[0] - 67
}
