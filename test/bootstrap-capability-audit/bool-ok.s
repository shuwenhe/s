package audit
func main() int {
    value := true
    if value && !false { return 42 }
    return 0
}
