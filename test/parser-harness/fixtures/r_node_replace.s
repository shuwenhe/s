package harness_recursive
struct Node { int value; Node* next }
func main() int {
    root := alloc(Node)
    root.next = alloc(Node)
    assert(live_allocations() == 2)
    root.next = alloc(Node)
    assert(live_allocations() == 2)
    root.next = nil
    assert(root.next == nil)
    assert(live_allocations() == 1)
    drop(root)
    assert(live_allocations() == 0)
    return 0
}
