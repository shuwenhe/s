package compile.internal.abt
func self_test() int {
    t1 := new_tree()
    ignored := insert(t1, 10, "10")
    ignored = insert(t1, 5, "5")
    ignored = insert(t1, 15, "15")
    if size(t1) != 3 {
        return 1
    }
    lo := min(t1)
    hi := max(t1)
    if !lo.ok || lo.key != 5 {
        return 1
    }
    if !hi.ok || hi.key != 15 {
        return 1
    }
    got := find(t1, 10)
    if got != "10" {
        return 1
    }
    d := delete(t1, 10)
    if d != "10" {
        return 1
    }
    if find(t1, 10) != "" {
        return 1
    }
    0
}
