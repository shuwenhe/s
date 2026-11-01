package harness_recursive
struct Node { int value; Node* next }
struct Other { int value }
func main() int { root := alloc(Node); root.next = alloc(Other); return 0 }
