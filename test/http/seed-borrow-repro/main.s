// Full std.http closure regression: nested borrows compile and the closed
// server returns the expected error without opening a socket.
package main
import "std.http"
func main() int {
    server := std.http.server { closed: true }
    event,error := std.http.serve_next(server*)
    if error.code != 9 { return 1 }
    return 0
}
