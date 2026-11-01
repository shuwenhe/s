package harness_alloc_double_drop

struct Cell { int value }

func main() int {
    object := alloc(Cell);
    drop(object);
    drop(object);
    return 0;
}
