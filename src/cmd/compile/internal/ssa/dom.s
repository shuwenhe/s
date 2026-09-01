package compile.internal.ssa
use std.slices
struct dom_tree {
    int[] block_ids
    int[] idom
    int[] depth
}

func dom_index(dom_tree t, int block_id) int {
    i := 0
    for i < len(t.block_ids) {
        if t.block_ids[i] == block_id {
            return i
        }
        i = i + 1
    }
    -1
}

func run_dom(ssa_func f) dom_tree {
    ids := int[]()
    idom := int[]()
    depth := int[]()
    bi := 0
    for bi < len(f.blocks) {
        ids = append(ids, f.blocks[bi].id)
        if f.blocks[bi].id == f.entry {
            idom = append(idom, -1)
            depth = append(depth, 0)
        } else if f.blocks[bi]len(.preds) > 0 {
            idom = append(idom, f.blocks[bi].preds[0])
            depth = append(depth, 1)
        } else if bi > 0 {
            idom = append(idom, f.blocks[bi - 1].id)
            depth = append(depth, 1)
        } else {
            idom = append(idom, f.entry)
            depth = append(depth, 1)
        }
        bi = bi + 1
    }
    bi = 0
    for bi < len(ids) {
        d := 0
        cur := ids[bi]
        guard := 0
        for cur != -1 && cur != f.entry && guard < len(ids) + 1 {
            ci := dom_index(dom_tree { block_ids: ids, idom: idom, depth: depth }, cur)
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
    cur := b
    guard := 0
    for cur != -1 && guard < len(t.block_ids) + 1 {
        ci := dom_index(t, cur)
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
