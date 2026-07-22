package main

func test_complex_arrays() void {
    var ints = []int{1, 2, 3, 4, 5}
    var floats = []float{1.0, 2.5, 3.14}
    var strings = []string{"a", "b", "c"}

    var trailing = []int{1, 2, 3,}

    print_array([]int{10, 20, 30})
}

func print_array([]int arr) void {
    println("Array length:", len(arr))
}

func main() int {
    test_complex_arrays()
    0
}
