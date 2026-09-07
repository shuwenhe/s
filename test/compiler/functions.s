package functions

func add(int left, int right) int {
    return left + right;
}

func consume(box value) int {
    result := *value;
    return result;
}

func main() int {
    value := box(40);
    result := consume(value);
    assert(live_allocations() == 0);
    return add(result, 2);
}
