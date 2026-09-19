// P0.5f Test: Does Stage1 support tuple returns?
package test

func get_pair() (int, string) {
    return 42, "hello"
}

func main() {
    a, b := get_pair()
    println(a)
    println(b)
}
