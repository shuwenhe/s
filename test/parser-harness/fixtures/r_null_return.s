package harness_recursive
struct Node { int value; Node* next }
func absent() Node* { return nil }
func main() int { node := absent(); assert(node == nil); drop(node); assert(live_allocations() == 0); return 0 }
