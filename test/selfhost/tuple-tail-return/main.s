package main
func pair() (string,string) { return "a", "b" }
func relay() (string,string) { pair() }
func main() int {
    a, b := relay()
    if a == "a" && b == "b" { return 42 }
    return 1
}
