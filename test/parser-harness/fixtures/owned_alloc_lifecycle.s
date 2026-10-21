package harness_owned_alloc

struct Cell { int value }

func main() int {
    assert(live_allocations() == 0);
    {
        object := alloc(Cell);
        assert(object.value == 0);
        assert(live_allocations() == 1);
        number := 42;
        object.value = number;
        assert(number == 42);
        moved := object;
        assert(moved.value == 42);
        assert(live_allocations() == 1);
        drop(moved);
        assert(live_allocations() == 0);
    }
    {
        automatic := alloc(Cell);
        automatic.value = 7;
        assert(live_allocations() == 1);
    }
    assert(live_allocations() == 0);
    return 0;
}
