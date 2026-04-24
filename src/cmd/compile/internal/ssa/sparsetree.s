package compile.internal.ssa

use std.vec.vec

struct sparse_tree_node {
    int parent
    int child
    int sibling
    int entry
    int exit
}

struct sparse_tree {
    vec[sparse_tree_node] nodes
}

func new_sparse_tree(int n) sparse_tree {
    var nodes = vec[sparse_tree_node]()
    var i = 0
    while i < n {
        nodes.push(sparse_tree_node {
            parent: -1,
            child: -1,
            sibling: -1,
            entry: 0,
            exit: 0,
        })
        i = i + 1
    }
    sparse_tree { nodes: nodes }
}

func sparse_tree_add_edge(mut sparse_tree t, int parent, int child) sparse_tree {
    if parent < 0 || child < 0 || parent >= t.nodes.len() || child >= t.nodes.len() {
        return t
    }
    t.nodes[child].parent = parent
    t.nodes[child].sibling = t.nodes[parent].child
    t.nodes[parent].child = child
    t
}

func number_subtree(mut sparse_tree t, int root, int n) int_pair {
    if root < 0 || root >= t.nodes.len() {
        return make_int_pair(n, 0)
    }
    var next = n + 1
    t.nodes[root].entry = next
    next = next + 2
    var child = t.nodes[root].child
    while child >= 0 {
        var r = number_subtree(t, child, next)
        next = r.left
        child = t.nodes[child].sibling
    }
    next = next + 1
    t.nodes[root].exit = next
    make_int_pair(next + 2, 1)
}

func sparse_tree_is_ancestor_eq(sparse_tree t, int x, int y) bool {
    if x < 0 || y < 0 || x >= t.nodes.len() || y >= t.nodes.len() {
        return false
    }
    if x == y {
        return true
    }
    t.nodes[x].entry <= t.nodes[y].entry && t.nodes[y].exit <= t.nodes[x].exit
}
