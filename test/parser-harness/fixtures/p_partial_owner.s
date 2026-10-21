package harness_pointer
struct Cell { box child; int value }
func read(Cell* cell) int { return cell.value }
func main() int { cell := Cell(box(1), 42); child := cell.child; return read(cell) }
