package harness_alloc_field_type

struct Cell { int value }

func main() int {
    object := alloc(Cell);
    object.value = "bad";
    return 0;
}
