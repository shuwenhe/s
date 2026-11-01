package harness_alloc_type_mismatch

struct Cell { int value }
struct Other { int value }

func read_other(Other object) int { return object.value; }

func main() int {
    object := alloc(Cell);
    return read_other(object);
}
