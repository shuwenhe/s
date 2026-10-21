package harness_h2_reference_type_mismatch
func read(ref string source) string { return *source; }
func main() int {
    value := 42;
    assert(read(&value) == "parser");
    return 0;
}
