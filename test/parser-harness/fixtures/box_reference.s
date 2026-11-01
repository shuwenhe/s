package harness_box_reference

func read(ref value) int { return *value; }

func main() int {
    owner := box(42);
    if read(&owner) != 42 { return 1; }
    return 0;
}
