package harness_shared_reference_write

func set(ref value) int {
    *value = 42;
    return *value;
}

func main() int {
    owner := box(7);
    return set(&owner);
}
