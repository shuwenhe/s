package main

func main() int {
    sum := 0;
    i := 1;
    while i <= 20000000 {
        sum = sum + i;
        i = i + 1;
    }
    return sum;
}
