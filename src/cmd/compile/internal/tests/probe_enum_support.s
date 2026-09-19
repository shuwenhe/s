// P0.5f Test: Does Stage1 support enum?
package test

enum my_enum {
    option_a(int),
    option_b(string),
}

func main() {
    x := option_a(42)
    println("done")
}
