package main
struct Box { int value; int[] items }
state := Box[]()
func churn() int {
    i := 0
    for i < 5000 {
        items := int[]()
        j := 0
        for j < 100 { items.push(i+j); j = j + 1 }
        i = i + 1
    }
    return 1
}
func nested(int depth, Box value) int {
    if depth > 0 { return nested(depth-1, value) }
    bump := churn()
    if bump != 1 || value.value != 41 || value.items[0] != 1 { return 2 }
    return value.value+value.items[0]
}
func hold(Box* value) int {
    bump := churn()
    if value.value != 41 || bump != 1 { return 2 }
    value.value = value.value + 1
    return value.value
}
func main() int {
    original := Box { value: 41, items: [1,2] }
    saved := original
    original.value = 99
    original.items[0] = 99
    state.push(saved)
    if nested(10, saved) != 42 { return 3 }
    if state[0].value != 41 || state[0].items[0] != 1 { return 4 }
    value := Box { value: 41 }
    if hold(value*) != 42 || value.value != 42 { return 5 }
    return 42
}
