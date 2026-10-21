package harness_h2_copy_mutable
func main() int {
    source := "parser";
    reference := &mut source;
    copied := reference;
    return 0;
}
