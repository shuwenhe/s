package harness_h2_scalar_field

struct Cell { int value; int other }
func set(mutref value) int { *value = 42; return *value; }

func main() int {
    object := alloc(Cell);
    object.other = 9;
    reference := &object.value;
    assert(*reference == 0);
    drop(reference);
    assert(set(&mut object.value) == 42);
    assert(object.value == 42);
    assert(object.other == 9);
    return 0;
}
