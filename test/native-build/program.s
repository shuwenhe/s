package main
func main(int input) int {
    product := multiply(input, 3)
    return product + 4
}
func multiply(int left, int right) int {
    return left * right
}
func unused() int { return 99 }
