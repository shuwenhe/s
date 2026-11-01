package harness_array_alloc

struct Cell { int value }

func main() int {
    objects := alloc_array(Cell, 2);
    objects[0].value = 42;
    objects[1].value = 7;
    if objects[0].value != 42 { return 1; }
    if objects[1].value != 7 { return 2; }
    return 0;
}
