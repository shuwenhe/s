package harness_h2_string_calls

func read(ref string source) string { return *source; }
func set(mutref string source) int { *source = "changed"; return 0; }

func main() int {
    source := "parser";
    reference := &source;
    assert(read(reference) == "parser");
    drop(reference);
    assert(set(&mut source) == 0);
    assert(source == "changed");
    assert(read(&source) == "changed");
    assert(live_allocations() == 0);
    return 0;
}
