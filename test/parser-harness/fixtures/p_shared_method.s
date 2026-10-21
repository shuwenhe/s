package harness_pointer
struct Cell { int value }
func (Cell* cell) write() { cell.value = 42 }
func call(ref Cell cell) { cell.write() }
func main() int { cell := alloc(Cell); call(cell); return 0 }
