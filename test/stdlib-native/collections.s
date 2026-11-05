package main
import ("std.collections"; "std.option")
func main() int {
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
    println("collections: PASS")
    return 0
}
