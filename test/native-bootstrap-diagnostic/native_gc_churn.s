package main
struct Box { int value; int[] items }
state := Box[]()
func churn() int {
    i := 0
    total := 0
    for i < 20000 {
        items := int[]()
        j := 0
        for j < 100 { items.push(i+j); j = j + 1 }
        if i == 1 { state.push(Box { value: 42, items: items }) }
        if i == 19999 { total = items[99] }
        i = i + 1
    }
    if total != 20098 { return 1 }
    if state[0].items[0] != 1 || state[0].items[99] != 100 { return 2 }
    return state[0].value
}
func main() int { return churn() }
