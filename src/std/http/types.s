package std.http
import "std.tcp"

// First HTTP slice: synchronous, IPv4, one bodyless request per connection.
// Like std.tcp.socket, a live server has one owner; do not copy it or use it
// concurrently. Shutdown is called by the owner between serve_next calls.
struct options {
    string host
    int port, int backlog
    int max_header_bytes, int max_request_line_bytes, int max_headers, int max_body_bytes
    int accept_timeout_ms, int read_timeout_ms, int write_timeout_ms
}
struct http_error { int code, int status, string message }
struct header { string name, string value }
struct request { string method, string target, string path, string host, string query, string body, int content_length, int header_bytes, header[] headers }
struct response { int status, string body, string content_type, header[] headers }
// pending owns exactly one accepted socket until respond/discard closes it.
struct pending { std.tcp.socket connection, request request, options config, bool closed, bool accepted }
struct exchange { int status, bool peer_eof }
struct server { std.tcp.socket listener, options config, bool closed }

func _problem(int status, string message) http_error {
    return http_error { code: 22, status: status, message: message }
}
func _options(options original) (options,http_error) {
    value := original
    if value.host == "" { value.host = "127.0.0.1" }
    if value.backlog == 0 { value.backlog = 128 }
    if value.max_header_bytes == 0 { value.max_header_bytes = 8192 }
    if value.max_request_line_bytes == 0 { value.max_request_line_bytes = 2048 }
    if value.max_headers == 0 { value.max_headers = 64 }
    if value.accept_timeout_ms == 0 { value.accept_timeout_ms = 100 }
    if value.read_timeout_ms == 0 { value.read_timeout_ms = 5000 }
    if value.write_timeout_ms == 0 { value.write_timeout_ms = 5000 }
    if value.max_body_bytes < 0 || value.max_body_bytes > 16777216 || value.port < 0 || value.port > 65535 || value.backlog < 1 || value.backlog > 65535 || value.max_header_bytes < 16 || value.max_header_bytes > 1048576 || value.max_request_line_bytes < 1 || value.max_request_line_bytes > value.max_header_bytes || value.max_headers < 1 || value.max_headers > 1024 || value.accept_timeout_ms < 1 || value.accept_timeout_ms > 2147483647 || value.read_timeout_ms < 1 || value.read_timeout_ms > 2147483647 || value.write_timeout_ms < 1 || value.write_timeout_ms > 2147483647 {
        return value,_problem(0,"invalid HTTP options")
    }
    return value,http_error {}
}
