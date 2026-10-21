package harness_h2_read_borrowed_field
struct Cell { int value }
func main() int {
    object := alloc(Cell);
    reference := &mut object.value;
    copied := object.value;
    assert(*reference == 0);
    return 0;
}
