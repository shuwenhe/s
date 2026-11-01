package harness_int_array
func main() int {
    count := 3;
    values := alloc_array(int, count);
    assert(len(values) == 3);
    assert(values[0] == 0);
    values[0] = 20;
    values[2] = 22;
    assert(values[0] + values[2] == 42);
    moved := values;
    assert(moved[2] == 22);
    drop(moved);
    assert(live_allocations() == 0);
    empty := alloc_array(int, 0);
    assert(len(empty) == 0);
    return 0;
}
