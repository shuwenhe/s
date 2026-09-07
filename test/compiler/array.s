package test.compiler

func main() int {
    values := [20, 22];
    assert(values[0] == 20);
    assert(values[1] == 22);
    values[1] = 23;
    assert(values[1] == 23);
    return values[0] + values[1] - 1;
}
