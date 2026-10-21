package harness_alloc

struct Cell { int value }

func main() int {
    object := alloc(Cell);
    object.value = 42;
    if object.value != 42 { return 1; }
    return 0;
}
