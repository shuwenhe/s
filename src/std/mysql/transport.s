package std.mysql
import ("std.database"; "std.database.wire"; "std.tcp"; "std.tls"; "std.time")

// Single owner, sequential operations. Never copy a live connection.
struct connection {
    std.tcp.socket socket
    std.tls.session secure
    std.database.options config
    bool encrypted
    bool closed
    bool in_transaction
    int sequence
    int deadline
    string identity
    int next_statement_token
    int[] active_statement_tokens
    int server_connection_id
    string server_version
}
func _u(int number, int width) string {
    bytes,error := std.database.wire.encode_uint(number,width,true)
    return bytes
}
func _zeroes(int count) string {
    output := ""
    index := 0
    while index < count { output = output + _u(0,1); index = index + 1 }
    return output
}
func _abort(connection* client) {
    if client.closed { return }
    if client.encrypted {
        secure := client.secure
        std.tls.close(secure*)
        client.secure = secure
    }
    socket := client.socket
    std.tcp.close(socket*)
    client.socket = socket
    client.closed = true
    client.in_transaction = false
}
func _fatal(connection* client, std.database.error problem) std.database.error {
    _abort(client*)
    return std.database.error { code: problem.code, message: problem.message, native_code: problem.native_code, sqlstate: problem.sqlstate, driver: "mysql", fatal: true }
}
func _transport_error(connection* client, int code, string operation) std.database.error {
    problem := std.database.error { code: std.database.error_transport, message: operation, native_code: code, driver: "mysql", fatal: true }
    return _fatal(client*,problem)
}
func _start_deadline(connection* client, int milliseconds) std.database.error {
    now,error := std.time.monotonic_clock()
    if error.code != 0 { return _transport_error(client*,error.code,"monotonic clock failed") }
    client.deadline = now + milliseconds * 1000000
    return std.database.error {}
}
func _remaining(int deadline, int timeout) int {
    now,error := std.time.monotonic_clock()
    if error.code != 0 || now >= deadline { return 0 }
    remaining := (deadline - now + 999999) / 1000000
    if remaining > timeout { remaining = timeout }
    return remaining
}
func _read_exact(connection* client, int size) (string,std.database.error) {
    output := ""
    while len(output) < size {
        remaining := _remaining(client.deadline,client.config.read_timeout_ms)
        if remaining == 0 { return "",_transport_error(client*,110,"MySQL read timeout") }
        maximum := size - len(output)
        if maximum > 65536 { maximum = 65536 }
        if client.encrypted {
            secure := client.secure
            chunk,error := std.tls.read_some(secure,maximum,remaining)
            if error.code != 0 { return "",_transport_error(client*,error.code,"MySQL TLS read failed") }
            if chunk.eof { return "",_transport_error(client*,104,"MySQL server disconnected") }
            output = output + chunk.data
        } else {
            socket := client.socket
            chunk,error := std.tcp.read_some(socket*,maximum,remaining)
            client.socket = socket
            if error.code != 0 { return "",_transport_error(client*,error.code,"MySQL TCP read failed") }
            if chunk.eof { return "",_transport_error(client*,104,"MySQL server disconnected") }
            output = output + chunk.data
        }
    }
    return output,std.database.error {}
}
func _read_packet(connection* client) (string,std.database.error) {
    header,error := _read_exact(client*,4)
    if error.code != 0 { return "",error }
    source := std.database.wire.cursor { data: header }
    length := std.database.wire.read_uint(source*,3,true)
    sequence := std.database.wire.read_byte(source*)
    if length > client.config.max_packet_bytes || sequence != client.sequence {
        problem := protocol_error("MySQL packet size or sequence mismatch")
        return "",_fatal(client*,problem)
    }
    client.sequence = (client.sequence + 1) % 256
    return _read_exact(client*,length)
}
func _write_packet(connection* client, string payload) std.database.error {
    sequence := client.sequence
    maximum := client.config.max_packet_bytes
    frame,error := encode_packet(payload,sequence,maximum)
    if error.code != 0 { return std.database.failure(error.code,error.message) }
    remaining := _remaining(client.deadline,client.config.write_timeout_ms)
    if remaining == 0 { return _transport_error(client*,110,"MySQL write timeout") }
    if client.encrypted {
        secure := client.secure
        written,problem := std.tls.write_all(secure*,frame,remaining)
        client.secure = secure
        if problem.code != 0 { return _transport_error(client*,problem.code,"MySQL TLS write failed") }
    } else {
        socket := client.socket
        written,problem := std.tcp.write_all(socket*,frame,remaining)
        client.socket = socket
        if problem.code != 0 { return _transport_error(client*,problem.code,"MySQL TCP write failed") }
    }
    client.sequence = (client.sequence + 1) % 256
    return std.database.error {}
}
func _command(connection* client, string payload) std.database.error {
    if client.closed { return std.database.failure(std.database.error_closed,"MySQL connection is closed") }
    // Bound a whole command, including slow fragmented responses.
    timeout := client.config.read_timeout_ms + client.config.write_timeout_ms
    problem := _start_deadline(client*,timeout)
    if problem.code != 0 { return problem }
    client.sequence = 0
    return _write_packet(client*,payload)
}
// Server ERR packets terminate a response. A malformed ERR is a fatal protocol
// failure, whereas an ordinary SQL error leaves the connection synchronized.
func _server_error(connection* client, string payload) std.database.error {
    problem := decode_error(payload)
    if problem.fatal { return _fatal(client*,problem) }
    return problem
}
