package compile.internal.tests.test_abt

use compile.internal.abt.new_tree
use compile.internal.abt.insert
use compile.internal.abt.find
use compile.internal.abt.size
use compile.internal.abt.min
use compile.internal.abt.max
use compile.internal.abt.glb
use compile.internal.abt.lub
use compile.internal.abt.delete_min
use compile.internal.abt.delete_max
use compile.internal.abt.union
use compile.internal.abt.intersection
use compile.internal.abt.difference
use compile.internal.abt.equals

func run_abt_suite() int {
    let t1 = new_tree()
    let ignored = insert(t1, 4, "4")
    ignored = insert(t1, 2, "2")
    ignored = insert(t1, 6, "6")
    ignored = insert(t1, 5, "5")

    if size(t1) != 4 {
        return 1
    }
    if find(t1, 2) != "2" {
        return 1
    }
    if find(t1, 99) != "" {
        return 1
    }

    let mi = min(t1)
    if !mi.ok || mi.key != 2 {
        return 1
    }
    let ma = max(t1)
    if !ma.ok || ma.key != 6 {
        return 1
    }

    let g = glb(t1, 5)
    if !g.ok || g.key != 4 {
        return 1
    }
    let l = lub(t1, 5)
    if !l.ok || l.key != 6 {
        return 1
    }

    let dmin = delete_min(t1)
    if !dmin.ok || dmin.key != 2 {
        return 1
    }
    let dmax = delete_max(t1)
    if !dmax.ok || dmax.key != 6 {
        return 1
    }
    if size(t1) != 2 {
        return 1
    }

    let a = new_tree()
    ignored = insert(a, 1, "a1")
    ignored = insert(a, 2, "a2")
    let b = new_tree()
    ignored = insert(b, 2, "b2")
    ignored = insert(b, 3, "b3")

    let u = union(a, b)
    if size(u) != 3 {
        return 1
    }

    let i = intersection(a, b)
    if size(i) != 1 || find(i, 2) == "" {
        return 1
    }

    let df = difference(a, b)
    if size(df) != 1 || find(df, 1) == "" || find(df, 2) != "" {
        return 1
    }

    let c = new_tree()
    ignored = insert(c, 1, "a1")
    ignored = insert(c, 2, "a2")
    if !equals(a, c) {
        return 1
    }

    0
}
