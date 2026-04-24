package compile.internal.ssa

use std.vec.vec

struct dom_tree {
    vec[int] block_ids
    vec[int] idom
    vec[int] depth
}

func dom_index(dom_tree t, int block_id) int {
    var i = 0
    while i < t.block_ids.len() {
        if t.block_ids[i] == block_id {
            return i
        }
        i = i + 1
    }
    -1
}

func run_dom(ssa_func f) dom_tree {
    var ids = vec[int]()
    var idom = vec[int]()
    var depth = vec[int]()

    var bi = 0
    while bi < f.blocks.len() {
        ids.push(f.blocks[bi].id)
        if f.blocks[bi].id == f.entry {
            idom.push(-1)
            depth.push(0)
        } else if f.blocks[bi].preds.len() > 0 {
            idom.push(f.blocks[bi].preds[0])
            depth.push(1)
        } else if bi > 0 {
            idom.push(f.blocks[bi - 1].id)
            depth.push(1)
        } else {
            idom.push(f.entry)
            depth.push(1)
        }
        bi = bi + 1
    }

    bi = 0
    while bi < ids.len() {
        var d = 0
        var cur = ids[bi]
        var guard = 0
        while cur != -1 && cur != f.entry && guard < ids.len() + 1 {
            var ci = dom_index(dom_tree { block_ids: ids, idom: idom, depth: depth }, cur)
            if ci < 0 {
                break
            }
            cur = idom[ci]
            d = d + 1
            guard = guard + 1
        }
        depth[bi] = d
        bi = bi + 1
    }

    dom_tree {
        block_ids: ids,
        idom: idom,
        depth: depth,
    }
}

func dominates(dom_tree t, int a, int b) bool {
    if a == b {
        return true
    }
    var cur = b
    var guard = 0
    while cur != -1 && guard < t.block_ids.len() + 1 {
        var ci = dom_index(t, cur)
        if ci < 0 {
            return false
        }
        cur = t.idom[ci]
        if cur == a {
            return true
        }
        guard = guard + 1
    }
    false
}
