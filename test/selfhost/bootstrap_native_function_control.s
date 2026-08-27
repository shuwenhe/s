package main

func choose(int value) int {
    result := 40
    if value > 10 {
        result = result + 2
    } else {
        result = 1
    }
    return result
}

func helper(int value) int {
    if value == 7 {
        return choose(20)
    }
    return 0
}

func main() int {
    return helper(7)
}
