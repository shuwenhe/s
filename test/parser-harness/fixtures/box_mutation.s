package harness_box_mutation

func set(mutref value) int {
    *value = 42;
    return *value;
}

func main() int {
    owner := box(7);
    if set(&mut owner) != 42 { return 1; }
    if *owner != 42 { return 2; }
    return 0;
}
