package harness_recursive
struct Node { int value; Node* next }
func main() int { root := alloc(Node); root.value = nil; return 0 }
