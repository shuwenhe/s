package harness_source_reference

func main() int {
    source := "parser";
    reference := &source;
    if len(*reference) != 6 { return 1; }
    return 0;
}
