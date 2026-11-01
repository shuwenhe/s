package harness_h2_upgrade_shared
func main() int {
    source := "parser";
    reference := &source;
    mutable := &mut *reference;
    return 0;
}
