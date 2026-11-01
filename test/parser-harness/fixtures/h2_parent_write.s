package harness_h2_parent_write
func main() int {
    source := "parser";
    reference := &mut source;
    child := &*reference;
    *reference = "changed";
    assert(*child == "parser");
    return 0;
}
