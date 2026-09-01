package bootstrap.closure
func identity(string value) string {
    return value
}

func main() {
    return len(identity("hello")) + identity("hello")[0] - 67
}
