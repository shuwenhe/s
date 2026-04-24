package compile.internal.abt

use std.vec.vec

var leaf_height = 1
var zero_height = 0
var not_key32 = -2147483648

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
    var copied = vec[kv32]()
    var i = 0
    while i < tree.items.len() {
        copied.push(tree.items[i])
        i = i + 1
    }
    t {
        items: copied,
        size: tree.size,
    }
}

func find(t tree, int key) string {
    var i = index_of_key(tree, key)
    if i < 0 {
        return ""
    }
    tree.items[i].data
}

func insert(t mut tree, int key, string data) string {
    if key == not_key32 {
        return ""
    }

    var i = index_of_key(tree, key)
    if i >= 0 {
        var old = tree.items[i].data
        tree.items.set(i, kv32 { key: key, data: data })
        return old
    }

    var pos = lower_bound(tree, key)
    var out = vec[kv32]()
    var p = 0
    while p < pos {
        out.push(tree.items[p])
        p = p + 1
    }
    out.push(kv32 { key: key, data: data })
    while p < tree.items.len() {
        out.push(tree.items[p])
        p = p + 1
    }
    tree.items = out
    tree.size = tree.items.len()
    ""
}

func delete(t mut tree, int key) string {
    var i = index_of_key(tree, key)
    if i < 0 {
        return ""
    }

    var old = tree.items[i].data
    var out = vec[kv32]()
    var p = 0
    while p < tree.items.len() {
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
    var v = tree.items[0]
    find_result { ok: true, key: v.key, data: v.data }
}

func max(t tree) find_result {
    if tree.items.len() == 0 {
        return find_result { ok: false, key: not_key32, data: "" }
    }
    var v = tree.items[tree.items.len() - 1]
    find_result { ok: true, key: v.key, data: v.data }
}

func delete_min(t mut tree) find_result {
    var m = min(tree)
    if !m.ok {
        return m
    }
    var ignored = delete(tree, m.key)
    m
}

func delete_max(t mut tree) find_result {
    var m = max(tree)
    if !m.ok {
        return m
    }
    var ignored = delete(tree, m.key)
    m
}

func glb(t tree, int key) find_result {
    var i = tree.items.len() - 1
    while i >= 0 {
        if tree.items[i].key < key {
            return find_result { ok: true, key: tree.items[i].key, data: tree.items[i].data }
        }
        i = i - 1
    }
    find_result { ok: false, key: not_key32, data: "" }
}

func glb_eq(t tree, int key) find_result {
    var i = tree.items.len() - 1
    while i >= 0 {
        if tree.items[i].key <= key {
            return find_result { ok: true, key: tree.items[i].key, data: tree.items[i].data }
        }
        i = i - 1
    }
    find_result { ok: false, key: not_key32, data: "" }
}

func lub(t tree, int key) find_result {
    var i = 0
    while i < tree.items.len() {
        if tree.items[i].key > key {
            return find_result { ok: true, key: tree.items[i].key, data: tree.items[i].data }
        }
        i = i + 1
    }
    find_result { ok: false, key: not_key32, data: "" }
}

func lub_eq(t tree, int key) find_result {
    var i = 0
    while i < tree.items.len() {
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

func next(iter32 mut it) find_result {
    if done(it) {
        return find_result { ok: false, key: not_key32, data: "" }
    }
    var v = it.items[it.index]
    it.index = it.index + 1
    find_result { ok: true, key: v.key, data: v.data }
}

func equals(t left, t right) bool {
    if left.size != right.size {
        return false
    }
    var i = 0
    while i < left.items.len() {
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
    var out = copy_tree(left)
    var i = 0
    while i < right.items.len() {
        var ignored = insert(out, right.items[i].key, right.items[i].data)
        i = i + 1
    }
    out
}

func intersection(t left, t right) t {
    var out = new_tree()
    var i = 0
    while i < left.items.len() {
        var d = find(right, left.items[i].key)
        if d != "" {
            var ignored = insert(out, left.items[i].key, left.items[i].data)
        }
        i = i + 1
    }
    out
}

func difference(t left, t right) t {
    var out = new_tree()
    var i = 0
    while i < left.items.len() {
        var d = find(right, left.items[i].key)
        if d == "" {
            var ignored = insert(out, left.items[i].key, left.items[i].data)
        }
        i = i + 1
    }
    out
}

func to_string(t tree) string {
    var out = ""
    var i = 0
    while i < tree.items.len() {
        if i > 0 {
            out = out + "; "
        }
        out = out + std.prelude.to_string(tree.items[i].key) + ":" + tree.items[i].data
        i = i + 1
    }
    out
}

func index_of_key(t tree, int key) int {
    var i = 0
    while i < tree.items.len() {
        if tree.items[i].key == key {
            return i
        }
        i = i + 1
    }
    -1
}

func lower_bound(t tree, int key) int {
    var i = 0
    while i < tree.items.len() {
        if tree.items[i].key > key {
            return i
        }
        i = i + 1
    }
    tree.items.len()
}
