package main
struct leaf { int value; string text }
struct node { leaf child; int sentinel }
func change(node n) node {
    n.child.value = 99
    return n
}
func seventh(int a, int b, int c, int d, int e, int f, node n) int {
    n.child.value = n.child.value + a + b + c + d + e + f
    return n.child.value
}
func main() int {
    a := node { sentinel: 7, child: leaf { text: "ok", value: 21 } }
    b := a
    b.child.value = 32
    if a.child.value != 21 { return 1 }
    returned := change(a)
    if returned.child.value != 99 { return 2 }
    if a.child.value != 21 { return 3 }
    if seventh(1, 2, 3, 4, 5, 6, a) != 42 { return 4 }
    if a.child.value != 21 { return 5 }
    if b.child.value != 32 { return 6 }
    if returned.sentinel != 7 { return 7 }
    return 42
}
