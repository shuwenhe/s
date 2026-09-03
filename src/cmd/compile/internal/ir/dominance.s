package compile.internal.ir.dominance

struct dominator_tree {
    i32[] immediate_dominator
    i32[][] dom_children
    i32[][] dom_frontier
    i32[][] strict_dom_frontier
    []bool computed
}

func new_dominator_tree(num_blocks i32) dominator_tree* {
    dt := new(dominator_tree)
    dt.immediate_dominator = make(i32[], num_blocks)
    dt.dom_children = make(i32[][], num_blocks)
    dt.dom_frontier = make(i32[][], num_blocks)
    dt.strict_dom_frontier = make(i32[][], num_blocks)
    dt.computed = make([]bool, num_blocks)
    
    for i := i32(0); i < num_blocks; i += 1 {
        dt.immediate_dominator[i] = -1
        dt.dom_children[i] = new i32[]()
        dt.dom_frontier[i] = new i32[]()
        dt.strict_dom_frontier[i] = new i32[]()
        dt.computed[i] = false
    }
    dt
}

func (dt dominator_tree*) compute_dominators(preds i32[][], entry i32) {
    n := i32(len(preds))
    dom := make([]bool[], n)
    
    for i := i32(0); i < n; i += 1 {
        dom[i] = make([]bool, n)
        for j := i32(0); j < n; j += 1 {
            dom[i][j] = true
        }
    }
    
    dom[entry][entry] = true
    for j := i32(0); j < n; j += 1 {
        if j != entry {
            dom[entry][j] = false
        }
    }
    
    changed := true
    for changed {
        changed = false
        for b := i32(0); b < n; b += 1 {
            if b == entry {
                continue
            }
            
            pred_list := preds[b]
            if len(pred_list) == 0 {
                continue
            }
            
            new_dom := make([]bool, n)
            for j := i32(0); j < n; j += 1 {
                new_dom[j] = true
            }
            
            for _, p := range pred_list {
                if p >= 0 && p < n {
                    for j := i32(0); j < n; j += 1 {
                        new_dom[j] = new_dom[j] && dom[p][j]
                    }
                }
            }
            
            new_dom[b] = true
            
            for j := i32(0); j < n; j += 1 {
                if new_dom[j] != dom[b][j] {
                    changed = true
                    dom[b][j] = new_dom[j]
                }
            }
        }
    }
    
    for b := i32(0); b < n; b += 1 {
        idom := -1
        for d := i32(0); d < n; d += 1 {
            if d != b && dom[b][d] {
                if idom == -1 {
                    idom = d
                } else {
                    is_strict := false
                    for j := i32(0); j < n; j += 1 {
                        if j != d && dom[d][j] && dom[idom][j] {
                            is_strict = true
                            break
                        }
                    }
                    if is_strict {
                        idom = d
                    }
                }
            }
        }
        dt.immediate_dominator[b] = idom
    }
    
    for b := i32(0); b < n; b += 1 {
        if dt.immediate_dominator[b] >= 0 {
            parent := dt.immediate_dominator[b]
            dt.dom_children[parent] = append(dt.dom_children[parent], b)
        }
    }
    
    for b := i32(0); b < n; b += 1 {
        dt.computed[b] = true
    }
}

func (dt dominator_tree*) compute_dominance_frontier(succs i32[][], preds i32[][]) {
    n := i32(len(preds))
    
    for b := i32(0); b < n; b += 1 {
        succ_list := succs[b]
        if len(succ_list) >= 2 {
            for _, w := range succ_list {
                if w >= 0 && w < n {
                    runner := b
                    for runner != dt.immediate_dominator[w] && dt.immediate_dominator[w] >= 0 {
                        dt.dom_frontier[runner] = append(dt.dom_frontier[runner], w)
                        runner = dt.immediate_dominator[runner]
                        if runner < 0 {
                            break
                        }
                    }
                }
            }
        }
    }
}

func (dt dominator_tree*) strictly_dominates(a i32, b i32) bool {
    if a == b {
        return false
    }
    
    runner := b
    for runner >= 0 {
        if runner == a {
            return true
        }
        runner = dt.immediate_dominator[runner]
    }
    false
}

func (dt dominator_tree*) get_idom(block i32) i32 {
    if block >= 0 && block < i32(len(dt.immediate_dominator)) {
        return dt.immediate_dominator[block]
    }
    -1
}

func (dt dominator_tree*) get_dom_children(block i32) i32[] {
    if block >= 0 && block < i32(len(dt.dom_children)) {
        return dt.dom_children[block]
    }
    new i32[]()
}

func (dt dominator_tree*) get_dominance_frontier(block i32) i32[] {
    if block >= 0 && block < i32(len(dt.dom_frontier)) {
        return dt.dom_frontier[block]
    }
    new i32[]()
}
