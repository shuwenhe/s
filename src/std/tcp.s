package std.tcp
import ("std.time"; "std.result")

// Linux/amd64, IPv4 literals. Each live socket has one owner: do not copy it.
// All returned errno values are positive. EOF is separate from errors and data.
struct tcp_error { int code, string operation }
struct socket { int descriptor, bool closed, bool eof, bool listener }
struct read_chunk { string data, bool eof }
extern "intrinsic" func __tcp_dial(int address, int port, int timeout_ms) int
extern "intrinsic" func __tcp_listen(int address, int port, int backlog) int
extern "intrinsic" func __tcp_accept(int fd, int timeout_ms) int
extern "intrinsic" func __tcp_port(int fd) int
extern "intrinsic" func __tcp_send(int fd, string data, int offset, int timeout_ms) int
extern "intrinsic" func __tcp_receive(int fd, int maximum, int timeout_ms) int[]
extern "intrinsic" func __tcp_close(int fd) int
extern "intrinsic" func __host_byte_at(string text, int index) int
extern "intrinsic" func __std_byte_string(int value) string
extern "intrinsic" func __string_slice(string text, int start, int end) string
func _error(int status, string operation) tcp_error {
    code := 0
    if status < 0 { code = 0 - status }
    return tcp_error { code: code, operation: operation }
}
func _address(string host) (int,tcp_error) {
    index := 0
    address := 0
    factor := 1
    part := 0
    while part < 4 {
        value := 0
        digits := 0
        while index < len(host) {
            byte := __host_byte_at(host,index)
            if byte < 48 || byte > 57 { break }
            value = value * 10 + byte - 48
            if value > 255 { return 0, _error(-22,"IPv4 address") }
            digits = digits + 1
            index = index + 1
        }
        if digits == 0 { return 0, _error(-22,"IPv4 address") }
        address = address + value * factor
        factor = factor * 256
        if part < 3 {
            if index >= len(host) || __host_byte_at(host,index) != 46 { return 0, _error(-22,"IPv4 address") }
            index = index + 1
        }
        part = part + 1
    }
    if index != len(host) { return 0, _error(-22,"IPv4 address") }
    return address,tcp_error { code: 0 }
}
func dial_ipv4(string host, int port, int timeout_ms) (socket,tcp_error) {
    address, error := _address(host)
    if error.code != 0 { return socket { closed: true, descriptor: -1 }, error }
    fd := __tcp_dial(address,port,timeout_ms)
    if fd < 0 { return socket { closed: true, descriptor: -1 }, _error(fd,"connect") }
    return socket { descriptor: fd }, tcp_error { code: 0 }
}
func listen_ipv4(string host, int port, int backlog) (socket,tcp_error) {
    address, error := _address(host)
    if error.code != 0 { return socket { closed: true, descriptor: -1 }, error }
    fd := __tcp_listen(address,port,backlog)
    if fd < 0 { return socket { closed: true, descriptor: -1 }, _error(fd,"listen") }
    return socket { descriptor: fd, listener: true }, tcp_error { code: 0 }
}
func local_port(socket listener) (int,tcp_error) {
    if listener.closed { return 0, _error(-9,"local port") }
    port := __tcp_port(listener.descriptor)
    if port < 0 { return 0, _error(port,"local port") }
    return port,tcp_error { code: 0 }
}
func accept(socket listener, int timeout_ms) (socket,tcp_error) {
    if listener.closed || !listener.listener { return socket { closed: true, descriptor: -1 }, _error(-9,"accept") }
    fd := __tcp_accept(listener.descriptor,timeout_ms)
    if fd < 0 { return socket { closed: true, descriptor: -1 }, _error(fd,"accept") }
    return socket { descriptor: fd }, tcp_error { code: 0 }
}
func write_some(socket connection, string data, int offset, int timeout_ms) (int,tcp_error) {
    if connection.closed || connection.listener { return 0, _error(-9,"write") }
    status := __tcp_send(connection.descriptor,data,offset,timeout_ms)
    if status < 0 { return 0, _error(status,"write") }
    return status,tcp_error { code: 0 }
}
func write_all(socket* connection, string data, int timeout_ms) (int,tcp_error) {
    if connection.closed || connection.listener { return 0, _error(-9,"write") }
    if timeout_ms < -1 || timeout_ms > 2147483647 { return 0, _error(-22,"write timeout") }
    fd := connection.descriptor
    deadline := 0
    if timeout_ms > 0 {
        now, clock_error := std.time.monotonic_clock()
        if clock_error.code != 0 { return 0, _error(0 - clock_error.code,"write clock") }
        deadline = now + timeout_ms * 1000000
    }
    written := 0
    while written < len(data) {
        remaining := timeout_ms
        if deadline != 0 {
            now, clock_error := std.time.monotonic_clock()
            if clock_error.code != 0 { return written, _error(0 - clock_error.code,"write clock") }
            if now >= deadline { return written, _error(-110,"write timeout") }
            remaining = (deadline - now + 999999) / 1000000
        }
        count := __tcp_send(fd,data,written,remaining)
        if count < 0 { return written, _error(count,"write") }
        if count == 0 { return written, _error(-5,"write made no progress") }
        written = written + count
    }
    return written,tcp_error { code: 0 }
}
func _bytes(int[] bytes, int start, int end) string {
    if start == end { return "" }
    if end - start == 1 { return __std_byte_string(bytes[start]) }
    middle := start + (end - start) / 2
    left := _bytes(bytes,start,middle)
    right := _bytes(bytes,middle,end)
    return left + right
}
func read_some(socket* connection, int maximum, int timeout_ms) (read_chunk,tcp_error) {
    if connection.closed || connection.listener { return read_chunk {}, _error(-9,"read") }
    if connection.eof { return read_chunk { eof: true }, tcp_error { code: 0 } }
    fd := connection.descriptor
    bytes := __tcp_receive(fd,maximum,timeout_ms)
    if len(bytes) == 0 { return read_chunk {}, _error(-12,"read allocation") }
    if bytes[0] < 0 { return read_chunk {}, _error(bytes[0],"read") }
    if len(bytes) == 1 { connection.eof = true; return read_chunk { eof: true }, tcp_error { code: 0 } }
    return read_chunk { data: _bytes(bytes,1,len(bytes)) }, tcp_error { code: 0 }
}
func close(socket* connection) tcp_error {
    if connection.closed { return tcp_error { code: 0 } }
    fd := connection.descriptor
    // Linux consumes close ownership even on EINTR; never retry a reused fd.
    status := __tcp_close(fd)
    connection.closed = true
    connection.descriptor = -1
    return _error(status,"close")
}
func byte_at(string text, int index) (int,tcp_error) {
    if index < 0 || index >= len(text) { return 0, _error(-22,"byte index") }
    return __host_byte_at(text,index),tcp_error { code: 0 }
}
func slice(string text, int start, int end) (string,tcp_error) {
    if start < 0 || end < start || end > len(text) { return "", _error(-22,"slice") }
    return __string_slice(text,start,end),tcp_error { code: 0 }
}
