package main
func classify(int value) int {
    int result
    if value < 0 {
        result = 1
    } else if value == 0 {
        result = 2
    } else {
        result = 3
    }
    return result
}

func sum6(int a, int b, int c, int d, int e, int f) int {
    return a + b + c + d + e + f
}

func main() {
    string marker = "selfhost"
    return sum6(classify(-1), classify(0), classify(1), 10, 11, 15)
}
