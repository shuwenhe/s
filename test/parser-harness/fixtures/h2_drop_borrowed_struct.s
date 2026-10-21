package harness_h2_drop_borrowed_struct
struct Cell { int value }
func main() int {
    object := alloc(Cell);
    reference := &object.value;
    drop(object);
    return *reference;
}
