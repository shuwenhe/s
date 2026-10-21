package harness_recursive
struct Node { int value; Node* next }
func main() int { root := alloc(Node); child := alloc(Node); root.next = child; return child.value }
