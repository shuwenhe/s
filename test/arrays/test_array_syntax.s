package main
func test_array_types() void {
    int[] arr1 = int[]{1, 2, 3}
    int[5] arr2 = int[5]{1, 2, 3, 4, 5}
    string[] arr3 = string[]{"a", "b"}
    string[10] arr4 = string[10]{"x"}
    print_array(arr1)
    print_fixed(arr2)
}

func print_array(int[] arr) void {
    println("Array length:", len(arr))
}

func print_fixed(int[5] arr) void {
    println("Fixed array")
}

func main() {
    test_array_types()
    0
}
