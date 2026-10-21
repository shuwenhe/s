package harness_alloc_unknown_field

struct Cell { int value }

func main() int {
    object := alloc(Cell);
    object.missing = 42;
    return 0;
}
