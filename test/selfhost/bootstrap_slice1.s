package main

func scale(int input) int {
    offset := 1
    if input > 10 {
        return 0
    } else {
        bonus := 0
        return input * 5 + offset + bonus
    }
}

func main() {
    base := scale(8)
    return base + 1
}
