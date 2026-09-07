package test.compiler

func sum(int[] values) int {
    assert(len(values) == 2);
    return values[0] + values[1] - 1;
}

func main() int {
    values := [20, 22];
    assert(len(values) == 2);
    assert(values[0] == 20);
    assert(values[1] == 22);
    values[1] = 23;
    assert(values[1] == 23);
    return sum(values);
}
