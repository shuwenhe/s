package harness_alloc_qualified

struct Cell { int value }

func main() int {
    object := alloc(harness_alloc_qualified.Cell);
    object.value = 42;
    assert(object.value == 42);
    return 0;
}
