package main
struct Event { string unit }
func create(string unit) Event { Event { unit: unit } }
func main() int {
    event := create("ok")
    if event.unit == "ok" { return 42 }
    return 1
}
