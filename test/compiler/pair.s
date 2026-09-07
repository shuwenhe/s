package test.compiler

func forward(pair p) pair {
    return p;
}

func sum(pair p) int {
    return *p.left + *p.right;
}

func main() int {
    {
        p := forward(pair(box(20), box(22)));
        assert(live_allocations() == 3);
        assert(sum(p) == 42);
        assert(live_allocations() == 0);
    }
    assert(live_allocations() == 0);
    return 42;
}
