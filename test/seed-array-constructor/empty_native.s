package array_constructor_test

func empty() int[] {
    return int[]()
}

func size(int[] values) int {
    return len(values)
}

func main() int {
    values := empty()
    return size(values)
}
