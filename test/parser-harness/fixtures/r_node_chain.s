package harness_recursive
struct Node { int value; Node* next }
func leaf(int value) Node* {
    node := alloc(Node)
    node.value = value
    return node
}
func sum(ref Node node) int {
    if node.next == nil { return node.value }
    return node.value + sum(node.next)
}
func main() int {
    first := leaf(10)
    assert(first.next == nil)
    second := leaf(12)
    third := leaf(20)
    second.next = third
    first.next = second
    assert(first.next.value == 12)
    assert(sum(first) == 42)
    assert(live_allocations() == 3)
    drop(first)
    assert(live_allocations() == 0)
    return 0
}
