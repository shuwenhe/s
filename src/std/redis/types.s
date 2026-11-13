package std.redis
import "std.prelude"
const error_invalid = 1
const error_bounds = 2
const error_closed = 3
const error_protocol = 4
const error_server = 5
const error_transport = 6
const error_timeout = 7
const error_state = 8
struct error { int code, int native_code, string message, bool fatal }
struct limits { int max_frame_bytes, int max_bulk_bytes, int max_array_length, int max_depth, int max_nodes }
struct node { string kind, string text, int integer, int parent, int length }
struct document { node[] nodes, int count }
struct decoder {
 limits config
 document doc
 string source
 int position
 int scan
 int bulk_length
 int bulk_node
 bool waiting_bulk
 int[] parents
 int[] remaining
 int depth
 bool complete
 error failure
}
struct options {
 string host
 int port
 int connect_timeout_ms
 int read_timeout_ms
 int write_timeout_ms
 string username
 string password
 int database
 bool use_tls
 string tls_server_name
 string tls_ca_file
 limits bounds
}
struct optional_string { bool present, string value }
struct set_options { int ex_seconds, int px_milliseconds, bool nx, bool xx }
struct command { string[] arguments }
struct batch { document[] replies, int count }
func _redis_error(int code, string message) error {
 return error {code:code,message:message}
}
func byte_string(int value) string {
 return __std_byte_string(value)
}
extern "intrinsic" func __std_byte_string(int value) string
extern "intrinsic" func __host_byte_at(string value, int index) int
extern "intrinsic" func __string_slice(string value, int start, int end) string
func _redis_limits(limits value) (limits,error) {
 c := value
 if c.max_frame_bytes == 0 { c.max_frame_bytes=1048576 }
 if c.max_bulk_bytes == 0 { c.max_bulk_bytes=c.max_frame_bytes }
 if c.max_array_length == 0 { c.max_array_length=4096 }
 if c.max_depth == 0 { c.max_depth=64 }
 if c.max_nodes == 0 { c.max_nodes=8192 }
 if c.max_frame_bytes < 1 || c.max_frame_bytes > 16777216 || c.max_bulk_bytes < 1 || c.max_bulk_bytes > c.max_frame_bytes || c.max_array_length < 1 || c.max_array_length > 65536 || c.max_depth < 1 || c.max_depth > 256 || c.max_nodes < 1 || c.max_nodes > 65536 { return c,_redis_error(error_invalid,"invalid RESP limits") }
 return c,error {}
}
