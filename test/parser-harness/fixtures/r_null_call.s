package harness_recursive
struct Node { int value; Node* next }
func read(ref Node node) int { return node.value }
func main() int { root := alloc(Node); return read(root.next) }
