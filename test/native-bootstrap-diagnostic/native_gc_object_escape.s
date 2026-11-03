package main
func main(int count) int[] {
    i := 0
    for i < count { discarded := [i]; i = i + 1 }
    answer := count
    if count == 0 { answer = 42 }
    return [answer]
}
