package main
func identity[t](t value) t { value }
func main(int input) int { return identity(input) + 41 }
