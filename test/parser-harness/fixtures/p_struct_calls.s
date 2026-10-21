package harness_pointer
struct Cell { int value; string text }
func set(cell* Cell, int value) { cell.value = value; cell.text = "updated" }
func forward(Cell* cell) { set(cell, 42) }
func read(ref Cell cell) int { return cell.value }
func main() int {
    cell := alloc(Cell)
    forward(cell)
    assert(cell.value == 42)
    assert(cell.text == "updated")
    set(&mut cell, 7)
    assert(read(&cell) == 7)
    assert(read(cell) == 7)
    drop(cell)
    assert(allocations() == 0)
    return 0
}
