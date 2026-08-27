package main

func false_path() int {
    return 0
}

func true_path() int {
    return 1
}

func main() int {
    if true_path() && !false_path() && (false_path() || true_path()) {
        return 42
    }
    return 1
}
