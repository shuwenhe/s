package harness_box_field_mutation

func set(mutref value) int {
    *value = 42;
    return *value;
}

func main() int {
    owner := pair(box(7), box(9));
    if set(&mut owner.left) != 42 { return 1; }
    if *owner.left != 42 { return 2; }
    if *owner.right != 9 { return 3; }
    return 0;
}
