package harness_pointer
struct Cell { int value }
struct Other { int value }
func read(Cell* cell) int { return cell.value }
func main() int { other := alloc(Other); return read(other) }
