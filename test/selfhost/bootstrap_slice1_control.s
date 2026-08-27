package main

func classify(int input) int {
    if input > 10 && input < 20 {
        if input == 11 || (1 / 0) == 0 {
            return 42
        }
        return 0
    } else {
        if !(input == 0) {
            return 1
        }
        return 2
    }
}

func main() int {
    return classify(11)
}
