package main

func base() int {
    return 40
}

func choose(bool enabled, int value) int {
    int result = 1
    bool accepted = enabled && value > 10
    if accepted {
        result = value + 2
    }
    return result
}

func main() {
    int answer = choose(true, base())
    return answer
}
