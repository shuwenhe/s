package harness_array_copy
struct Entry { int kind; string text }
func main() int {
    source := alloc_array(Entry, 2);
    target := alloc_array(Entry, 4);
    source[0].kind = 5;
    source[0].text = "function";
    copy_array(target, source, 2);
    assert(target[0].kind == 5);
    assert(target[0].text == "function");
    target[0].kind = 42;
    assert(source[0].kind == 5);
    copy_array(target, target, 4);
    assert(target[0].kind == 42);
    integers := alloc_array(int, 2);
    integers[0] = 42;
    other := alloc_array(int, 2);
    copy_array(other, integers, 2);
    assert(other[0] == 42);
    return 0;
}
