package harness_h2_conflicting_mutable
func main() int {
    source := "parser";
    first := &mut source;
    second := &mut source;
    assert(*first == "parser");
    assert(*second == "parser");
    return 0;
}
