package harness_pointer
struct Cell { int value }
func write(Cell* cell) { cell.value = 1 }
func forward(ref Cell cell) { write(cell) }
func main() int { cell := alloc(Cell); forward(cell); return 0 }
