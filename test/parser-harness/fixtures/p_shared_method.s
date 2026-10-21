package harness_pointer
struct Cell { int value }
func (Cell* cell) write() int { return 42 }
func call(ref Cell cell) int { return cell.write() }
func main() int { cell := alloc(Cell); return call(cell) }
