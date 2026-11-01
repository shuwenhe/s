package harness_independent_borrows

func first() int {
    object := pair(box(20), box(22));
    reference := &object.left;
    return *reference;
}

func second() int {
    object := pair(box(7), box(9));
    reference := &mut object.left;
    *reference = 42;
    return *reference;
}

func main() int {
    if first() != 20 { return 1; }
    if second() != 42 { return 2; }
    return 0;
}
