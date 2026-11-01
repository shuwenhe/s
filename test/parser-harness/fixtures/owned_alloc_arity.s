package harness_alloc_arity

struct Cell { int value }

func main() int {
    object := alloc(Cell, 1);
    return 0;
}
