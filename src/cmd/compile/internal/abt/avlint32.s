package compile.internal.abt
use std.vec.vec
leaf_height := 1
zero_height := 0
not_key32 := -2147483648

struct kv32 {
    int key
    string data
}

struct t {
    vec[kv32] items
    int size
}

struct iter32 {
    vec[kv32] items
    int index
}

struct find_result {
    bool ok
    int key
    string data
}

func new_tree() t {
    t {
        items: vec[kv32](),
        size: 0,
    }
}

func is_empty(t tree) bool {
    tree.size == 0
}

func is_single(t tree) bool {
    tree.size == 1
}

func size(t tree) int {
    tree.size
}

func copy_tree(t tree) t {
    copied := vec[kv32]()
    i := 0
    for i < tree.items.len() {
        copied.push(tree.items[i])
        i = i + 1
    }
    t {
        items: copied,
        size: tree.size,
    }
}

func find(t tree, int key) string {
    i := index_of_key(tree, key)
    if i < 0 {
        return ""
    }
    tree.items[i].data
}

func insert(t tree, int key, string data) string {
    if key == not_key32 {
        return ""
    }
    i := index_of_key(tree, key)
    if i >= 0 {
        old := tree.items[i].data
        tree.items.set(i, kv32 { key: key, data: data })
        return old
    }
    pos := lower_bound(tree, key)
    out := vec[kv32]()
    p := 0
    for p < pos {
        out.push(tree.items[p])
        p = p + 1
    }
    out.push(kv32 { key: key, data: data })
    for p < tree.items.len() {
        out.push(tree.items[p])
        p = p + 1
    }
    tree.items = out
    tree.size = tree.items.len()
    ""
}

func delete(t tree, int key) string {
    i := index_of_key(tree, key)
    if i < 0 {
        return ""
    }
    old := tree.items[i].data
    out := vec[kv32]()
    p := 0
    for p < tree.items.len() {
        if p != i {
            out.push(tree.items[p])
        }
        p = p + 1
    }
    tree.items = out
    tree.size = tree.items.len()
    old
}

func min(t tree) find_result {
    if tree.items.len() == 0 {
        return find_result { ok: false, key: not_key32, data: "" }
    }
    v := tree.items[0]
    find_result { ok: true, key: v.key, data: v.data }
}

func max(t tree) find_result {
    if tree.items.len() == 0 {
        return find_result { ok: false, key: not_key32, data: "" }
    }
    v := tree.items[tree.items.len() - 1]
    find_result { ok: true, key: v.key, data: v.data }
}

func delete_min(t tree) find_result {
    m := min(tree)
    if !m.ok {
        return m
    }
    ignored := delete(tree, m.key)
    m
}

func delete_max(t tree) find_result {
    m := max(tree)
    if !m.ok {
        return m
    }
    ignored := delete(tree, m.key)
    m
}

func glb(t tree, int key) find_result {
    i := tree.items.len() - 1
    for i >= 0 {
        if tree.items[i].key < key {
            return find_result { ok: true, key: tree.items[i].key, data: tree.items[i].data }
        }
        i = i - 1
    }
    find_result { ok: false, key: not_key32, data: "" }
}

func glb_eq(t tree, int key) find_result {
    i := tree.items.len() - 1
    for i >= 0 {
        if tree.items[i].key <= key {
            return find_result { ok: true, key: tree.items[i].key, data: tree.items[i].data }
        }
        i = i - 1
    }
    find_result { ok: false, key: not_key32, data: "" }
}

func lub(t tree, int key) find_result {
    i := 0
    for i < tree.items.len() {
        if tree.items[i].key > key {
            return find_result { ok: true, key: tree.items[i].key, data: tree.items[i].data }
        }
        i = i + 1
    }
    find_result { ok: false, key: not_key32, data: "" }
}

func lub_eq(t tree, int key) find_result {
    i := 0
    for i < tree.items.len() {
        if tree.items[i].key >= key {
            return find_result { ok: true, key: tree.items[i].key, data: tree.items[i].data }
        }
        i = i + 1
    }
    find_result { ok: false, key: not_key32, data: "" }
}

func iterator(t tree) iter32 {
    iter32 {
        items: tree.items,
        index: 0,
    }
}

func done(iter32 it) bool {
    it.index >= it.items.len()
}

func next(iter32 it) find_result {
    if done(it) {
        return find_result { ok: false, key: not_key32, data: "" }
    }
    v := it.items[it.index]
    it.index = it.index + 1
    find_result { ok: true, key: v.key, data: v.data }
}

func equals(t left, t right) bool {
    if left.size != right.size {
        return false
    }
    i := 0
    for i < left.items.len() {
        if left.items[i].key != right.items[i].key {
            return false
        }
        if left.items[i].data != right.items[i].data {
            return false
        }
        i = i + 1
    }
    true
}

func union(t left, t right) t {
    out := copy_tree(left)
    i := 0
    for i < right.items.len() {
        ignored := insert(out, right.items[i].key, right.items[i].data)
        i = i + 1
    }
    out
}

func intersection(t left, t right) t {
    out := new_tree()
    i := 0
    for i < left.items.len() {
        d := find(right, left.items[i].key)
        if d != "" {
            ignored := insert(out, left.items[i].key, left.items[i].data)
        }
        i = i + 1
    }
    out
}

func difference(t left, t right) t {
    out := new_tree()
    i := 0
    for i < left.items.len() {
        d := find(right, left.items[i].key)
        if d == "" {
            ignored := insert(out, left.items[i].key, left.items[i].data)
        }
        i = i + 1
    }
    out
}

func to_string(t tree) string {
    out := ""
    i := 0
    for i < tree.items.len() {
        if i > 0 {
            out = out + "; "
        }
        out = out + std.prelude.to_string(tree.items[i].key) + ":" + tree.items[i].data
        i = i + 1
    }
    out
}

func index_of_key(t tree, int key) int {
    i := 0
    for i < tree.items.len() {
        if tree.items[i].key == key {
            return i
        }
        i = i + 1
    }
    -1
}

func lower_bound(t tree, int key) int {
    i := 0
    for i < tree.items.len() {
        if tree.items[i].key > key {
            return i
        }
        i = i + 1
    }
    tree.items.len()
}
