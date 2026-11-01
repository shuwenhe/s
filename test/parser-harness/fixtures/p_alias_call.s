package harness_pointer
struct Cell { int value }
func write(Cell* a, Cell* b) { a.value = b.value }
func main() int { cell := alloc(Cell); write(cell, cell); return 0 }
