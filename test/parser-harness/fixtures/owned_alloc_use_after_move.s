package harness_alloc_use_after_move

struct Cell { int value }

func main() int {
    object := alloc(Cell);
    moved := object;
    return object.value;
}
