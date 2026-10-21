package harness_pointer
struct Cell { box value }
func take(Cell* cell) box { return cell.value }
func main() int { cell := Cell(box(1)); value := take(cell); return *value }
