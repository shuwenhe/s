package harness_h2_assign_borrowed_local
func main() int {
    source := "parser";
    reference := &source;
    source = "changed";
    assert(*reference == "parser");
    return 0;
}
