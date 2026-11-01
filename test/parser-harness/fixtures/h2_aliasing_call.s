package harness_h2_aliasing_call
func set_both(mutref string first, mutref string second) int {
    *first = "first";
    *second = "second";
    return 0;
}
func main() int {
    source := "parser";
    set_both(&mut source, &mut source);
    return 0;
}
