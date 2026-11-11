package std.tls
import ("std.tcp"; "std.time"; "std.result")

// Canonical raw ABI + system OpenSSL. Use build-openssl-client.py. TCP ownership
// remains with the caller; close TLS first, then TCP. No insecure verification mode.
struct tls_error { int code, string operation }
struct session { int handle, bool closed }
extern "intrinsic" func __tls_connect(int fd, string hostname, string ca_file, int timeout_ms) int
extern "intrinsic" func __tls_send(int handle, string data, int offset, int timeout_ms) int
extern "intrinsic" func __tls_receive(int handle, int[] buffer, int timeout_ms) int
extern "intrinsic" func __tls_close(int handle) int
func _error(int status, string operation) tls_error {
    code := 0
    if status < 0 { code = 0 - status }
    return tls_error { code: code, operation: operation }
}
func connect(std.tcp.socket connection, string hostname, string ca_file, int timeout_ms) (session,tls_error) {
    if connection.closed || connection.listener { return session { closed: true },_error(-9,"TLS connect") }
    handle := __tls_connect(connection.descriptor,hostname,ca_file,timeout_ms)
    if handle < 0 { return session { closed: true },_error(handle,"TLS handshake or certificate validation") }
    return session { handle: handle },tls_error { code: 0 }
}
func write_all(session* secure, string data, int timeout_ms) (int,tls_error) {
    if secure.closed { return 0,_error(-9,"TLS write") }
    if timeout_ms < -1 || timeout_ms > 2147483647 { return 0,_error(-22,"TLS timeout") }
    handle := secure.handle
    deadline := 0
    if timeout_ms > 0 {
        now,error := std.time.monotonic_clock()
        if error.code != 0 { return 0,_error(0 - error.code,"TLS clock") }
        deadline = now + timeout_ms * 1000000
    }
    written := 0
    while written < len(data) {
        remaining := timeout_ms
        if deadline != 0 {
            now,error := std.time.monotonic_clock()
            if error.code != 0 { return written,_error(0 - error.code,"TLS clock") }
            if now >= deadline { return written,_error(-110,"TLS write timeout") }
            remaining = (deadline - now + 999999) / 1000000
        }
        count := __tls_send(handle,data,written,remaining)
        if count < 0 { return written,_error(count,"TLS write") }
        if count == 0 { return written,_error(-5,"TLS write made no progress") }
        written = written + count
    }
    return written,tls_error { code: 0 }
}
func read_some(session secure, int maximum, int timeout_ms) (std.tcp.read_chunk,tls_error) {
    if secure.closed { return std.tcp.read_chunk {},_error(-9,"TLS read") }
    if maximum < 1 || maximum > 65536 { return std.tcp.read_chunk {},_error(-22,"TLS read size") }
    buffer := make([]int,maximum)
    count := __tls_receive(secure.handle,buffer,timeout_ms)
    if count < 0 { return std.tcp.read_chunk {},_error(count,"TLS read") }
    if count == 0 { return std.tcp.read_chunk { eof: true },tls_error { code: 0 } }
    return std.tcp.read_chunk { data: std.tcp._bytes(buffer,0,count) },tls_error { code: 0 }
}
func close(session* secure) tls_error {
    if secure.closed { return tls_error { code: 0 } }
    handle := secure.handle
    status := __tls_close(handle)
    secure.closed = true
    secure.handle = 0
    return _error(status,"TLS close")
}
