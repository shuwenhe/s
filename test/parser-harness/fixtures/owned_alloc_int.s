package harness_alloc_int

func main() int {
    object := alloc(int);
    assert(*object == 0);
    *object = 42;
    moved := object;
    assert(*moved == 42);
    drop(moved);
    assert(live_allocations() == 0);
    return 0;
}
