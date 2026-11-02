package main
struct Node { Node[] tail }
func main() int {
    root := Node[]()
    i := 0
    for i < 2200000 { root = [Node { tail: root }]; i = i + 1 }
    // Trigger a collection after the entire graph has become reachable.
    j := 0
    for j < 5000000 { unused := [j]; j = j + 1 }
    count := 0
    for len(root) != 0 { root = root[0].tail; count = count + 1 }
    if count != 2200000 { return 1 }
    return 42
}
