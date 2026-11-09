package allocation_library
struct node { int value }
struct state { node[] nodes }
func create() state { return state{nodes: make(node[], 2)} }
func allocate() node[] { return make([]node, 3) }
package main
func main() int {
    state current = create()
    node[] other = allocate()
    if len(current.nodes) == 2 && len(other) == 3 { return 0 }
    return 1
}
