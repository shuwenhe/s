package harness_record_array
struct Entry { int kind; string text; int line; int col }
func main() int {
    entries := alloc_array(Entry, 2);
    assert(entries[0].kind == 0);
    assert(entries[0].text == "");
    entry := Entry(5, "function", 7, 9);
    entries[0] = entry;
    assert(live_allocations() == 2);
    assert(entries[0].kind == 5);
    assert(entries[0].text == "function");
    assert(entries[0].line == 7);
    assert(entries[0].col == 9);
    entries[1].kind = 20;
    entries[1].text = "package";
    assert(entries[1].kind == 20);
    assert(entries[1].text == "package");
    {
        loaded := entries[0];
        assert(live_allocations() == 3);
        loaded.kind = 42;
        assert(entries[0].kind == 5);
    }
    assert(live_allocations() == 2);
    return 0;
}
