package main

func fib(int n) int {
    if n <= 1 {
        n
    } else {
        fib(n - 1) + fib(n - 2)
    }
}

func main() int {
    fib(10)
}
