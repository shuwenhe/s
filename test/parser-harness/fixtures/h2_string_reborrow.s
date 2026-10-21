package harness_h2_string_reborrow

func main() int {
    source := "parser";
    reference := &mut source;
    child := &*reference;
    assert(*child == "parser");
    drop(child);
    *reference = "changed";
    drop(reference);
    assert(source == "changed");
    return 0;
}
