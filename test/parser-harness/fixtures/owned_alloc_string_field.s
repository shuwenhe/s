package harness_alloc_string_field

struct Entry {
    string label
    int value
}

func main() int {
    object := alloc(Entry);
    assert(object.label == "");
    assert(object.value == 0);
    object.label = "parser";
    assert(object.label == "parser");
    drop(object);
    assert(live_allocations() == 0);
    return 0;
}
