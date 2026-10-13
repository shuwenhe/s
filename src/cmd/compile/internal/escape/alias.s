package compile.internal.escape

struct alias_edge {
    int left
    int right
}

struct alias_set {
    alias_edge[] edges
}

func new_alias_set() alias_set {
    alias_set {}
}

func alias_add(alias_set aliases, int left, int right) {
}

func alias_may_alias(alias_set aliases, int left, int right) bool {
    if left == right {
        return true
    }
    i := 0
    for i < len(aliases.edges) {
        edge := aliases.edges[i]
        if edge.left == left && edge.right == right {
            return true
        }
        if edge.left == right && edge.right == left {
            return true
        }
        i = i + 1
    }
    false
}
