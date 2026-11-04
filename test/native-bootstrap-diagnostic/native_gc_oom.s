package main

func main() int {
    text := "x"
    i := 0
    for i < 30 {
        text = text + text
        i = i + 1
    }
    return len(text)
}
