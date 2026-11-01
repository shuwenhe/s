package main
struct item { int number }
func mutate(item[] values) item[] {
    values[0].number = 99
    return values
}
func main() int {
    a := item { number: 20 }
    b := item { number: 22 }
    items := [a, b];
    copied := items
    copied[0].number = 7
    if items[0].number != 20 { return 1 }
    changed := mutate(items)
    if changed[0].number != 99 { return 2 }
    if items[0].number != 20 { return 3 }
    if copied[1].number != 22 { return 4 }
    if items[0].number + items[1].number != 42 { return 5 }
    return 42
}
