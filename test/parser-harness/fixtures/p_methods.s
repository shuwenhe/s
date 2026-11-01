package harness_pointer
struct Cell { int value }
func (Cell* cell) increment() int { cell.value = cell.value + 1; return cell.value }
func call(Cell* cell) int { return cell.increment() }
func main() int { cell := alloc(Cell); assert(call(cell) == 1); assert(cell.value == 1); return 0 }
