package test.compiler

func sum(int[] values) int {
    assert(len(values) == 2);
    return values[0] + values[1] - 1;
}

func sum_shared(int[] left, int[] right) int {
    return left[0] + right[0];
}

func bump(mutint[] values) int {
    values[0] = values[0] + 1;
    return values[0];
}

func make_slice() slice {
    values := [20, 22];
    return slice(values);
}

func sum_slice(slice values) int {
    values[1] = values[1] + 1;
    return values[0] + values[1] - 1;
}

func read_slice(slice[] values) int {
    return values[0] + values[1];
}

func mutate_slice(mutslice[] values) int {
    values[0] = values[0] + 1;
    return values[0];
}

func main() int {
    values := [20, 22];
    assert(len(values) == 2);
    assert(values[0] == 20);
    assert(values[1] == 22);
    values[1] = 23;
    assert(values[1] == 23);
    assert(bump(values) == 21);
    assert(values[0] == 21);
    assert(sum_shared(values, values) == 42);
    s := make_slice();
    assert(live_allocations() == 2);
    assert(sum_slice(s) == 42);
    assert(live_allocations() == 0);
    s = make_slice();
    assert(read_slice(s) == 42);
    assert(mutate_slice(s) == 21);
    assert(read_slice(s) == 43);
    drop(s);
    assert(live_allocations() == 0);
    return sum(values) - 1;
}
