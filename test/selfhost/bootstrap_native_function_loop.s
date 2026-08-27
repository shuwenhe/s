package main

func multiply_by_loop(int value, int count) int {
    index := 0
    total := 0
    while index < count {
        total = total + value
        index = index + 1
    }
    return total
}

func helper(int value) int {
    return multiply_by_loop(value, 6)
}

func main() int {
    return helper(7)
}
