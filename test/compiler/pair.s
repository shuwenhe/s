package test.compiler

func forward(pair p) pair {
    return p;
}

func sum(pair p) int {
    return *p.left + *p.right;
}

func borrowed_pair_field() int {
    p := pair(box(20), box(22));
    r := &p.left;
    *p.right = 23;
    return *r + *p.right;
}

func mutable_pair_field() int {
    p := pair(box(20), box(22));
    r := &mut p.left;
    *r = 21;
    return *r;
}

func main() int {
    {
        p := forward(pair(box(20), box(22)));
        assert(live_allocations() == 3);
        assert(sum(p) == 42);
        assert(live_allocations() == 0);
    }
    assert(borrowed_pair_field() == 43);
    assert(mutable_pair_field() == 21);
    assert(live_allocations() == 0);
    return 42;
}