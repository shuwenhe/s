package harness_h2_string_field
struct Entry { string label }
func set(mutref string label) int { *label = "changed"; return 0; }
func main() int {
    object := alloc(Entry);
    reference := &object.label;
    assert(*reference == "");
    drop(reference);
    set(&mut object.label);
    assert(object.label == "changed");
    return 0;
}
