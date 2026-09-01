package main
func choose(string operator) string {
    if operator == "==" { return "equal" }
    if operator == "!=" { return "different" }
    if operator == "<" { return "less" }
    return "greater"
}

func main() {
    if choose("==") == "equal" {
        return 42
    }
    return 1
}
