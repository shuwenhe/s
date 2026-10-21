package harness_h2_local_int

func read(ref value) int { return *value; }
func set(mutref value) int { *value = 42; return *value; }

func main() int {
    value := 7;
    reference := &value;
    assert(read(reference) == 7);
    drop(reference);
    assert(set(&mut value) == 42);
    assert(value == 42);
    assert(live_allocations() == 0);
    return 0;
}
