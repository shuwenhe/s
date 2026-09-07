package test.compiler

func sum(int[] values) int {
    assert(len(values) == 2);
    return values[0] + values[1] - 1;
}

func bump(mutint[] values) int {
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
    return sum(values);
}
