package main
import "std.kafka"
func main() int {
    result := apiversions_checks()
    if result != 0 { return result }
    return broker_checks()
}
