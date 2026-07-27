package main

func test_let_immutable() void {
    let x = 10
    println("let x = 10 is immutable")
}

func test_var_mutable() void {
    var y = 5
    println("var y = 5 is mutable")
    y = 15
    println("var y reassigned to 15")
}

func test_let_array() void {
    let arr = []int{1, 2, 3}
    println("let arr = []int{1, 2, 3}")
}

func test_var_array() void {
    var arr = []int{1, 2, 3}
    println("var arr = []int{1, 2, 3}")
    arr = []int{4, 5}
    println("var arr reassigned to []int{4, 5}")
}

func main() int {
    test_let_immutable()
    test_var_mutable()
    test_let_array()
    test_var_array()
    0
}
