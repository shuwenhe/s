package harness_recursive
struct Node { int value; Node* next }
func main() int { root := alloc(Node); return root.next.value }
