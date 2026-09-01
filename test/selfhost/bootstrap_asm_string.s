package main
func decorate(string value) string {
    string prefix = "S:"
    return prefix + value
}

func main() {
    string actual = decorate("bootstrap")
    if actual == "S:bootstrap" {
        return 42
    }
    return 1
}
