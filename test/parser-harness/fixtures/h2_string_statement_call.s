package harness_h2_string_statement_call
func set(mutref string source) int { *source = "changed"; return 0; }
func main() int {
    source := "parser";
    set(&mut source);
    assert(source == "changed");
    return 0;
}
