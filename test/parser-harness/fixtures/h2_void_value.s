package harness_h2_void_value
func set(mutref string source) { *source = "changed"; }
func main() int {
    source := "parser";
    value := set(&mut source);
    return 0;
}
