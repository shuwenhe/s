package main
struct leaf { int value; string text }
struct state { leaf child; bool ready; int[] numbers }
func main() int {
    s := state {}
    if s.child.value != 0 { return 1 }
    if s.child.text != "" { return 2 }
    if s.ready { return 3 }
    if len(s.numbers) != 0 { return 4 }
    return 42
}
