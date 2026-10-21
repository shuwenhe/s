package harness_h2_field_scope
struct Cell { int value }
func main() int {
    object := alloc(Cell);
    {
        reference := &object.value;
        assert(*reference == 0);
    }
    mutable := &mut object.value;
    *mutable = 42;
    drop(mutable);
    assert(object.value == 42);
    return 0;
}
