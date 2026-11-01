package harness_alloc_borrow

func set(mutref value) int { *value = 42; return *value; }
func read(ref value) int { return *value; }

func main() int {
    object := alloc(int);
    assert(set(&mut object) == 42);
    assert(read(&object) == 42);
    drop(object);
    assert(live_allocations() == 0);
    return 0;
}
