package harness_h2_shared_string_write
func main() int {
    source := "parser";
    reference := &source;
    *reference = "changed";
    return 0;
}
