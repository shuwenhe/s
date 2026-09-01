package main
func test_let_immutable() void {
    x := 10
    println("x := 10 is immutable")
}

func test_var_mutable() void {
    var y = 5
    println("var y = 5 is mutable")
    y = 15
    println("var y reassigned to 15")
}

func test_let_array() void {
    arr := int[]{1, 2, 3}
    println("arr := int[]{1, 2, 3}")
}

func test_var_array() void {
    var arr = int[]{1, 2, 3}
    println("var arr = int[]{1, 2, 3}")
    arr = int[]{4, 5}
    println("var arr reassigned to int[]{4, 5}")
}

func main() {
    test_let_immutable()
    test_var_mutable()
    test_let_array()
    test_var_array()
    0
}
