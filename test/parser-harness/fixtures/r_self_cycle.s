package harness_recursive
struct Node { int value; Node* next }
func main() int { root := alloc(Node); root.next = root; return 0 }
