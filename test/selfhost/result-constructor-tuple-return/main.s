package main
import "std.result"
struct failure { string message }
func wrap(int value) (int, failure) {
    return result.ok(value)
}
func main() int { return 42 }
