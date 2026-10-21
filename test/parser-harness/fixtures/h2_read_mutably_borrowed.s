package harness_h2_read_mutably_borrowed
func main() int {
    source := "parser";
    reference := &mut source;
    copied := source;
    assert(*reference == "parser");
    return 0;
}
