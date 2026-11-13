package main
struct cell { int value }
func create() (cell,int) { return cell { value: 1 },0 }
func reset(cell* value) int { value.value = 42; return value.value }
func nested(cell* outer) int {
    local,error := create()
    return reset(local*)
}
func main() int {
    outer := cell {}
    answer := nested(outer*)
    if answer != 42 || outer.value != 0 { return 1 }
    return 0
}
