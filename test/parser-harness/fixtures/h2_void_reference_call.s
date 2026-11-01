package harness_h2_void_reference_call
func set(mutref string source) { *source = "changed"; }
func main() int {
    source := "parser";
    set(&mut source);
    assert(source == "changed");
    return 0;
}
