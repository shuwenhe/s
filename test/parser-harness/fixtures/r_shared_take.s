package harness_recursive
struct Node { int value; Node* next }
func take(ref Node node) Node* { return node.next }
func main() int { root := alloc(Node); child := take(root); return child.value }
