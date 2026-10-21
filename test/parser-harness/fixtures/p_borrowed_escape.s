package harness_pointer
struct Cell { int value }
func escape(Cell* cell) Cell { return cell }
func main() int { cell := alloc(Cell); copy := escape(cell); return copy.value }
