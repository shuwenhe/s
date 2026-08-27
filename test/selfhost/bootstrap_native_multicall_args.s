package main

func add3(int first, int second, int third) int {
    return first + second + third
}

func combine(int value) int {
    return add3(value, value, 1)
}

func main() int {
    return combine(10) * 2
}
