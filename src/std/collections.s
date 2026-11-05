package std.collections
import ("std.option"; "std.result"; "std.prelude")

struct collection_error { int code }
struct entry[v] { string key, v value }
struct _node[v] { string key, v value, int height, int count, _node[v][] left, _node[v][] right }
struct ordered_map[v] { _node[v][] root, int length }
struct set { ordered_map[bool] storage }
struct vector[t] { ordered_map[t] storage, int length }
struct stack[t] { vector[t] storage }
struct queue[t] { stack[t] front, stack[t] back, int length }
struct iterator[v] { ordered_map[v] snapshot, int position }

func _height[v](_node[v][] root) int {
    if len(root) == 0 { return 0 }
    return root[0].height
}
func _count[v](_node[v][] root) int {
    if len(root) == 0 { return 0 }
    return root[0].count
}
func _make_node[v](string key, v value, _node[v][] left, _node[v][] right) _node[v][] {
    height := _height(left)
    if _height(right) > height { height = _height(right) }
    node := _node[v] { key: key, value: value, height: height + 1, count: _count(left) + _count(right) + 1, left: left, right: right }
    return [node]
}
func _rotate_left[v](_node[v][] root) _node[v][] {
    node := root[0]
    pivot := node.right[0]
    left := _make_node(node.key, node.value, node.left, pivot.left)
    return _make_node(pivot.key, pivot.value, left, pivot.right)
}
func _rotate_right[v](_node[v][] root) _node[v][] {
    node := root[0]
    pivot := node.left[0]
    right := _make_node(node.key, node.value, pivot.right, node.right)
    return _make_node(pivot.key, pivot.value, pivot.left, right)
}
func _balance[v](_node[v][] root) _node[v][] {
    node := root[0]
    difference := _height(node.left) - _height(node.right)
    if difference > 1 {
        left := node.left
        if _height(left[0].right) > _height(left[0].left) { left = _rotate_left(left) }
        return _rotate_right(_make_node(node.key, node.value, left, node.right))
    }
    if difference < -1 {
        right := node.right
        if _height(right[0].left) > _height(right[0].right) { right = _rotate_right(right) }
        return _rotate_left(_make_node(node.key, node.value, node.left, right))
    }
    return root
}
func _insert[v](_node[v][] root, string key, v value) _node[v][] {
    if len(root) == 0 { return _make_node(key, value, root, root) }
    node := root[0]
    if key < node.key { return _balance(_make_node(node.key, node.value, _insert(node.left,key,value), node.right)) }
    if node.key < key { return _balance(_make_node(node.key, node.value, node.left, _insert(node.right,key,value))) }
    return _make_node(key, value, node.left, node.right)
}
func _remove[v](_node[v][] root, string key) _node[v][] {
    if len(root) == 0 { return root }
    node := root[0]
    if key < node.key { return _balance(_make_node(node.key, node.value, _remove(node.left,key), node.right)) }
    if node.key < key { return _balance(_make_node(node.key, node.value, node.left, _remove(node.right,key))) }
    if len(node.left) == 0 { return node.right }
    if len(node.right) == 0 { return node.left }
    successor := node.right[0]
    while len(successor.left) > 0 { successor = successor.left[0] }
    return _balance(_make_node(successor.key, successor.value, node.left, _remove(node.right,successor.key)))
}
func new_map[v](string[] keys, v[] values) (ordered_map[v],collection_error) {
    source := ordered_map[v] { length: 0 }
    if len(keys) != len(values) { return source, collection_error { code: 22 } }
    index := 0
    while index < len(keys) {
        updated, error := map_put(source,keys[index],values[index])
        if error.code != 0 { return source, error }
        source = updated
        index = index + 1
    }
    return source, collection_error { code: 0 }
}
func map_get[v](ordered_map[v] source, string key) option[v] {
    current := source.root
    while len(current) > 0 {
        node := current[0]
        if key < node.key { current = node.left } else {
            if node.key < key { current = node.right } else { return option.some(node.value) }
        }
    }
    return option[v].none
}
func map_put[v](ordered_map[v] source, string key, v value) (ordered_map[v],collection_error) {
    length := source.length
    if map_get(source,key).is_none() {
        if length == 9223372036854775807 { return source, collection_error { code: 75 } }
        length = length + 1
    }
    return ordered_map[v] { root: _insert(source.root,key,value), length: length }, collection_error { code: 0 }
}
func map_remove[v](ordered_map[v] source, string key) ordered_map[v] {
    if map_get(source,key).is_none() { return source }
    return ordered_map[v] { root: _remove(source.root,key), length: source.length - 1 }
}
func entries[v](ordered_map[v] source) iterator[v] { return iterator[v] { snapshot: source, position: 0 } }
func next_entry[v](iterator[v] cursor) (iterator[v],option[entry[v]]) {
    if cursor.position < 0 || cursor.position >= cursor.snapshot.length { return cursor, option[entry[v]].none }
    rank := cursor.position
    current := cursor.snapshot.root
    while len(current) > 0 {
        node := current[0]
        left_count := _count(node.left)
        if rank < left_count { current = node.left } else {
            if rank > left_count { rank = rank - left_count - 1; current = node.right } else {
                item := entry[v] { key: node.key, value: node.value }
                return iterator[v] { snapshot: cursor.snapshot, position: cursor.position + 1 }, option.some(item)
            }
        }
    }
    return cursor, option[entry[v]].none
}
func _index_key(int index) string {
    text := std.prelude.to_string(index)
    while len(text) < 19 { text = "0" + text }
    return text
}
func new_vector[t](t[] values) (vector[t],collection_error) {
    storage := ordered_map[t] { length: 0 }
    source := vector[t] { storage: storage, length: 0 }
    index := 0
    while index < len(values) {
        updated, error := vector_push(source,values[index])
        if error.code != 0 { return source, error }
        source = updated
        index = index + 1
    }
    return source, collection_error { code: 0 }
}
func vector_get[t](vector[t] source, int index) option[t] {
    if index < 0 || index >= source.length { return option[t].none }
    return map_get(source.storage,_index_key(index))
}
func vector_push[t](vector[t] source, t value) (vector[t],collection_error) {
    if source.length == 9223372036854775807 { return source, collection_error { code: 75 } }
    storage, error := map_put(source.storage,_index_key(source.length),value)
    if error.code != 0 { return source, error }
    return vector[t] { storage: storage, length: source.length + 1 }, error
}
func vector_set[t](vector[t] source, int index, t value) (vector[t],collection_error) {
    if index < 0 || index >= source.length { return source, collection_error { code: 22 } }
    storage, error := map_put(source.storage,_index_key(index),value)
    if error.code != 0 { return source, error }
    return vector[t] { storage: storage, length: source.length }, error
}
func vector_pop[t](vector[t] source) (vector[t],option[t]) {
    if source.length == 0 { return source, option[t].none }
    item := map_get(source.storage,_index_key(source.length - 1))
    storage := map_remove(source.storage,_index_key(source.length - 1))
    return vector[t] { storage: storage, length: source.length - 1 }, item
}
func new_stack[t](t[] values) (stack[t],collection_error) {
    storage, error := new_vector(values)
    return stack[t] { storage: storage }, error
}
func stack_push[t](stack[t] source, t value) (stack[t],collection_error) {
    storage, error := vector_push(source.storage,value)
    return stack[t] { storage: storage }, error
}
func stack_pop[t](stack[t] source) (stack[t],option[t]) {
    storage, value := vector_pop(source.storage)
    return stack[t] { storage: storage }, value
}
func new_queue[t](t[] values) (queue[t],collection_error) {
    front, error := new_stack(t[]())
    back, back_error := new_stack(values)
    if back_error.code != 0 { return queue[t] { front: front, back: front, length: 0 }, back_error }
    return queue[t] { front: front, back: back, length: len(values) }, error
}
func enqueue[t](queue[t] source, t value) (queue[t],collection_error) {
    if source.length == 9223372036854775807 { return source, collection_error { code: 75 } }
    back, error := stack_push(source.back,value)
    if error.code != 0 { return source, error }
    return queue[t] { front: source.front, back: back, length: source.length + 1 }, error
}
func dequeue[t](queue[t] source) (queue[t],option[t]) {
    if source.length == 0 { return source, option[t].none }
    front := source.front
    back := source.back
    if front.storage.length == 0 {
        while back.storage.length > 0 {
            remaining, item := stack_pop(back)
            back = remaining
            moved, error := stack_push(front,item.unwrap())
            if error.code != 0 { panic("queue invariant: transfer overflow") }
            front = moved
        }
    }
    remaining, item := stack_pop(front)
    return queue[t] { front: remaining, back: back, length: source.length - 1 }, item
}
func new_set(string[] keys) (set,collection_error) {
    storage := ordered_map[bool] { length: 0 }
    index := 0
    while index < len(keys) {
        updated, error := map_put(storage,keys[index],true)
        if error.code != 0 { return set { storage: storage }, error }
        storage = updated
        index = index + 1
    }
    return set { storage: storage }, collection_error { code: 0 }
}
func set_contains(set source, string key) bool { return map_get(source.storage,key).is_some() }
func set_add(set source, string key) (set,collection_error) {
    storage, error := map_put(source.storage,key,true)
    return set { storage: storage }, error
}
func set_remove(set source, string key) set { return set { storage: map_remove(source.storage,key) } }
