package main

func main() int {
    sum := 0
    for (i := 1; i <= 20000000; i = i + 1) {
        sum = sum + i
    }
    return sum
}
