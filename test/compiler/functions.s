package functions

func add(int left, int right) int {
    return left + right;
}

func consume(box value) int {
    result := *value;
    return result;
}

func read(ref value) int {
    return *value;
}

func bump(mutref value) int {
    *value = *value + 1;
    return *value;
}

func main() int {
    value := box(40);
    result := consume(value);
    assert(live_allocations() == 0);
    value = box(result);
    assert(bump(&mut value) == 41);
    assert(read(&value) == 41);
    return add(read(&value), 1);
}