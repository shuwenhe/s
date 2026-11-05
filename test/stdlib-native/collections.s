package main
import ("std.collections"; "std.option"; "std.prelude"; "std.time")
extern "intrinsic" func host_args() string[]
extern "intrinsic" func __std_byte_string(int value) string
func validate_tree[t](std.collections._node[t][] root, string lower, bool has_lower, string upper, bool has_upper) int {
    if len(root) == 0 { return 0 }
    if len(root) != 1 { panic("tree link cardinality") }
    node := root[0]
    if has_lower && node.key <= lower { panic("tree lower ordering") }
    if has_upper && node.key >= upper { panic("tree upper ordering") }
    left := validate_tree(node.left,lower,has_lower,node.key,true)
    right := validate_tree(node.right,node.key,true,upper,has_upper)
    if left - right > 1 || right - left > 1 { panic("AVL balance") }
    height := left
    if right > height { height = right }
    if node.height != height + 1 { panic("stored height") }
    count := 1
    if len(node.left) > 0 { count = count + node.left[0].count }
    if len(node.right) > 0 { count = count + node.right[0].count }
    if node.count != count { panic("subtree count") }
    return height + 1
}
func randomized_map_rules() int {
    source, error := std.collections.new_map(string[](),int[]())
    if error.code != 0 { return 30 }
    expected := int[]()
    present := bool[]()
    index := 0
    while index < 127 { expected = append(expected,0); present = append(present,false); index = index + 1 }
    seed := 20261105
    step := 0
    while step < 256 {
        seed = (seed * 1103515245 + 12345) & 2147483647
        key := seed % 127
        spelling := std.prelude.to_string(key)
        if (seed >> 10) % 4 != 0 {
            updated, update_error := std.collections.map_put(source,spelling,seed)
            if update_error.code != 0 { return 31 }
            source = updated
            expected[key] = seed
            present[key] = true
        } else {
            source = std.collections.map_remove(source,spelling)
            present[key] = false
        }
        height := validate_tree(source.root,"",false,"",false)
        count := 0
        index = 0
        while index < 127 {
            if present[index] { count = count + 1 }
            if step % 16 == 0 {
                found := std.collections.map_get(source,std.prelude.to_string(index))
                if found.is_some() != present[index] { return 32 }
                if present[index] && found.unwrap_or(-1) != expected[index] { return 33 }
            }
            index = index + 1
        }
        if source.length != count { return 34 }
        step = step + 1
    }
    cursor := std.collections.entries(source)
    previous := ""
    index = 0
    while index < source.length {
        advanced, found := std.collections.next_entry(cursor)
        if found.is_none() { return 35 }
        item := found.unwrap()
        if index > 0 && item.key <= previous { return 36 }
        previous = item.key
        cursor = advanced
        index = index + 1
    }
    ended, no_item := std.collections.next_entry(cursor)
    if !no_item.is_none() { return 37 }
    return 0
}
func collection_benchmark(int count) int {
    values, error := std.collections.new_vector(int[]())
    if error.code != 0 { return 50 }
    clock, clock_error := std.time.timer_start()
    if clock_error.code != 0 { return 51 }
    index := 0
    while index < count {
        updated, push_error := std.collections.vector_push(values,index)
        if push_error.code != 0 { return 52 }
        values = updated
        index = index + 1
    }
    elapsed, elapsed_error := std.time.elapsed_time(clock)
    if elapsed_error.code != 0 { return 53 }
    println("vector_count=" + std.prelude.to_string(count) + " push_ns=" + std.prelude.to_string(elapsed.nanoseconds))
    height := validate_tree(values.storage.root,"",false,"",false)
    if height > 16 { return 54 }
    index = 0
    total := 0
    while index < count {
        total = total + std.collections.vector_get(values,index).unwrap_or(-1)
        index = index + 1
    }
    if total != count * (count - 1) / 2 { return 55 }
    return 0
}
func main() int {
    args := host_args()
    if len(args) > 1 {
        if args[1] == "--benchmark" { return collection_benchmark(8192) }
        if args[1] == "--benchmark-seed" { return collection_benchmark(512) }
    }
    original, original_error := std.collections.new_map(string[](),string[]())
    if original_error.code != 0 { return 20 }
    values, error := std.collections.map_put(original, "2", "two")
    if error.code != 0 || original.length != 0 || values.length != 1 { return 1 }
    next, next_error := std.collections.map_put(values, "1", "one")
    if next_error.code != 0 || std.collections.map_get(next, "1").unwrap_or("") != "one" || !std.collections.map_get(values, "1").is_none() { return 2 }
    changed, changed_error := std.collections.map_put(next, "2", "TWO")
    if changed_error.code != 0 || changed.length != 2 || std.collections.map_get(values, "2").unwrap_or("") != "two" { return 3 }
    removed := std.collections.map_remove(changed, "1")
    if removed.length != 1 || !std.collections.map_get(removed, "1").is_none() { return 4 }
    vector, vector_error := std.collections.new_vector(int[]())
    if vector_error.code != 0 { return 21 }
    index := 0
    while index < 128 {
        updated, push_error := std.collections.vector_push(vector, index)
        if push_error.code != 0 { return 5 }
        vector = updated
        index = index + 1
    }
    if vector.length != 128 || std.collections.vector_get(vector,127).unwrap_or(-1) != 127 { return 6 }
    invalid, invalid_error := std.collections.vector_set(vector,128,0)
    if invalid_error.code != 22 || invalid.length != 128 { return 7 }
    snapshot := vector
    updated, update_error := std.collections.vector_set(vector,0,999)
    if update_error.code != 0 || std.collections.vector_get(snapshot,0).unwrap_or(-1) != 0 || std.collections.vector_get(updated,0).unwrap_or(-1) != 999 { return 8 }
    small, last := std.collections.vector_pop(vector)
    if small.length != 127 || last.unwrap_or(-1) != 127 || vector.length != 128 { return 9 }
    queue, queue_error := std.collections.new_queue(int[]())
    if queue_error.code != 0 { return 22 }
    index = 0
    while index < 64 {
        enqueued, enqueue_error := std.collections.enqueue(queue,index)
        if enqueue_error.code != 0 { return 10 }
        queue = enqueued
        index = index + 1
    }
    index = 0
    while index < 64 {
        dequeued, item := std.collections.dequeue(queue)
        if item.unwrap_or(-1) != index { return 11 }
        queue = dequeued
        index = index + 1
    }
    empty_queue, missing := std.collections.dequeue(queue)
    if !missing.is_none() { return 12 }
    set, constructor_error := std.collections.new_set(string[]())
    if constructor_error.code != 0 { return 23 }
    added, set_error := std.collections.set_add(set,"alpha")
    if set_error.code != 0 || !std.collections.set_contains(added,"alpha") || std.collections.set_contains(set,"alpha") { return 13 }
    deleted := std.collections.set_remove(added,"alpha")
    if std.collections.set_contains(deleted,"alpha") { return 14 }
    cursor := std.collections.entries(changed)
    cursor2, first := std.collections.next_entry(cursor)
    cursor3, second := std.collections.next_entry(cursor2)
    cursor4, end := std.collections.next_entry(cursor3)
    if first.unwrap().key != "1" || second.unwrap().key != "2" || !end.is_none() { return 15 }
    if randomized_map_rules() != 0 { return 40 }
    mismatched, mismatch_error := std.collections.new_map(string[]{"x"},int[]())
    if mismatch_error.code != 22 || mismatched.length != 0 { return 41 }
    fifo, fifo_error := std.collections.new_queue(int[]{1,2})
    if fifo_error.code != 0 { return 42 }
    fifo_snapshot := fifo
    fifo2, first_fifo := std.collections.dequeue(fifo)
    fifo3, fifo_push_error := std.collections.enqueue(fifo2,3)
    fifo4, second_fifo := std.collections.dequeue(fifo3)
    fifo5, third_fifo := std.collections.dequeue(fifo4)
    old_fifo, old_first := std.collections.dequeue(fifo_snapshot)
    if fifo_push_error.code != 0 || first_fifo.unwrap_or(-1) != 1 || second_fifo.unwrap_or(-1) != 2 || third_fifo.unwrap_or(-1) != 3 || old_first.unwrap_or(-1) != 1 || fifo5.length != 0 { return 43 }
    filled_set, filled_set_error := std.collections.new_set(string[]{"a","b","a"})
    if filled_set_error.code != 0 || filled_set.storage.length != 2 { return 44 }
    false_map, false_error := std.collections.new_map(string[]{"a"},bool[]{false})
    if false_error.code != 0 || !std.collections.map_get(false_map,"a").is_some() || std.collections.map_get(false_map,"a").unwrap_or(true) { return 45 }
    child := int[]{7}
    aggregate, aggregate_error := std.collections.new_vector([child])
    child[0] = 99
    stored := std.collections.vector_get(aggregate,0).unwrap()
    if aggregate_error.code != 0 || stored[0] != 7 { return 46 }
    stored[0] = 88
    preserved := std.collections.vector_get(aggregate,0).unwrap()
    if preserved[0] != 7 { return 47 }
    nul := __std_byte_string(0)
    high := __std_byte_string(255)
    binary_map, binary_error := std.collections.new_map([high,"a",nul,""],int[]{4,3,2,1})
    if binary_error.code != 0 { return 48 }
    binary_cursor := std.collections.entries(binary_map)
    binary_index := 1
    while binary_index <= 4 {
        binary_advanced, binary_item := std.collections.next_entry(binary_cursor)
        if binary_item.unwrap().value != binary_index { return 49 }
        binary_cursor = binary_advanced
        binary_index = binary_index + 1
    }
    println("collections: PASS")
    return 0
}
