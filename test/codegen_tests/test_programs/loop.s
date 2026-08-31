package main

func loop_sum(int n) int {
    int sum = 0
    int i = 0
    for i < n {
        sum = sum + i
        i = i + 1
    }
    sum
}

func main() int {
    loop_sum(10)
}
