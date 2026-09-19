// P0.5f Test: Does Stage1 support struct?
package test

struct my_struct {
    string name
    int value
}

func main() {
    x := my_struct { name: "test", value: 42 }
    println(x.name)
}
