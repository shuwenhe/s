package harness_cross_call

struct Cell { int value }

func set(Cell* object) {
    object.value = 42;
}

func main() int {
    object := alloc(Cell);
    object.value = 7;
    set(object);
    if object.value != 42 { return 1; }
    return 0;
}
