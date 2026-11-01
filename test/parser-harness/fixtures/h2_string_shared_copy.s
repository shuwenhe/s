package harness_h2_string_shared_copy

func main() int {
    source := "parser";
    reference := &source;
    other := reference;
    drop(reference);
    assert(*other == "parser");
    drop(other);
    source = "changed";
    assert(source == "changed");
    return 0;
}
