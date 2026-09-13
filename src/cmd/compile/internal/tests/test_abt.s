package compile.internal.tests.test_abt
import (
    "compile.internal.abt"
)
func run_abt_suite() int {
    t1 := compile.internal.abt.new_tree()
    ignored := compile.internal.abt.insert(t1, 4, "4")
    ignored = compile.internal.abt.insert(t1, 2, "2")
    ignored = compile.internal.abt.insert(t1, 6, "6")
    ignored = compile.internal.abt.insert(t1, 5, "5")
    if compile.internal.abt.size(t1) != 4 {
        return 1
    }
    if compile.internal.abt.find(t1, 2) != "2" {
        return 1
    }
    if compile.internal.abt.find(t1, 99) != "" {
        return 1
    }
    mi := compile.internal.abt.min(t1)
    if !mi.ok || mi.key != 2 {
        return 1
    }
    ma := compile.internal.abt.max(t1)
    if !ma.ok || ma.key != 6 {
        return 1
    }
    g := compile.internal.abt.glb(t1, 5)
    if !g.ok || g.key != 4 {
        return 1
    }
    l := compile.internal.abt.lub(t1, 5)
    if !l.ok || l.key != 6 {
        return 1
    }
    dmin := compile.internal.abt.delete_min(t1)
    if !dmin.ok || dmin.key != 2 {
        return 1
    }
    dmax := compile.internal.abt.delete_max(t1)
    if !dmax.ok || dmax.key != 6 {
        return 1
    }
    if compile.internal.abt.size(t1) != 2 {
        return 1
    }
    a := compile.internal.abt.new_tree()
    ignored = compile.internal.abt.insert(a, 1, "a1")
    ignored = compile.internal.abt.insert(a, 2, "a2")
    b := compile.internal.abt.new_tree()
    ignored = compile.internal.abt.insert(b, 2, "b2")
    ignored = compile.internal.abt.insert(b, 3, "b3")
    u := compile.internal.abt.union(a, b)
    if compile.internal.abt.size(u) != 3 {
        return 1
    }
    i := compile.internal.abt.intersection(a, b)
    if compile.internal.abt.size(i) != 1 || compile.internal.abt.find(i, 2) == "" {
        return 1
    }
    df := compile.internal.abt.difference(a, b)
    if compile.internal.abt.size(df) != 1 || compile.internal.abt.find(df, 1) == "" || compile.internal.abt.find(df, 2) != "" {
        return 1
    }
    c := compile.internal.abt.new_tree()
    ignored = compile.internal.abt.insert(c, 1, "a1")
    ignored = compile.internal.abt.insert(c, 2, "a2")
    if !compile.internal.abt.equals(a, c) {
        return 1
    }
    0
}
