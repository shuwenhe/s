package main

func test_array_types() void {
    []int arr1 = []int{1, 2, 3}
    [5]int arr2 = [5]int{1, 2, 3, 4, 5}
    []string arr3 = []string{"a", "b"}
    [10]string arr4 = [10]string{"x"}

    print_array(arr1)
    print_fixed(arr2)
}

func print_array([]int arr) void {
    println("Array length:", len(arr))
}

func print_fixed([5]int arr) void {
    println("Fixed array")
}

func main() int {
    test_array_types()
    0
}
