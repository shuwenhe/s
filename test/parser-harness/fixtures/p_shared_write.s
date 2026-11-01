package harness_pointer
struct Cell { int value }
func write(ref Cell cell) { cell.value = 1 }
func main() int { cell := alloc(Cell); write(cell); return 0 }
