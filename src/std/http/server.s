package std.http
import ("std.tcp"; "std.time")

func listen(options requested) (server,http_error) {
    config,error := _options(requested)
    if error.code != 0 { return server { closed: true },error }
    listener,problem := std.tcp.listen_ipv4(config.host,config.port,config.backlog)
    if problem.code != 0 { return server { closed: true },http_error { code: problem.code, message: problem.operation } }
    return server { listener: listener, config: config },http_error {}
}
func local_port(server* value) (int,http_error) {
    if value.closed { return 0,http_error { code: 9, message: "server closed" } }
    port,error := std.tcp.local_port(value.listener)
    return port,http_error { code: error.code, message: error.operation }
}
func shutdown(server* value) http_error {
    if value.closed { return http_error {} }
    // No background work exists: the owner calls this between exchanges.
    error := std.tcp.close(value.listener*)
    value.closed = true
    return http_error { code: error.code, message: error.operation }
}
// Only a complete, valid HEAD method token is enough to suppress a response
// body, even if later framing fails. No target/header data is trusted here.
func _request_method(string data) string {
    if len(data) >= 5 && __string_slice(data,0,5) == "HEAD " { return "HEAD" }
    return ""
}
func _read_request(std.tcp.socket* connection, options config) (request,http_error) {
    data := ""
    started,clock_error := std.time.monotonic_clock()
    if clock_error.code != 0 { return request { method: _request_method(data) },http_error { code: clock_error.code, message: "header clock" } }
    deadline := started + config.read_timeout_ms * 1000000
    scanned := 0
    while true {
        end := _header_end_from(data,scanned)
        if end == -2 { return request { method: _request_method(data) },_problem(400,"invalid CRLF framing") }
        if end >= 0 {
            parsed,parse_error := parse_request(data,config)
            if parse_error.code != 0 { parsed.method = _request_method(data); return parsed,parse_error }
            available := len(data) - end
            if available > parsed.content_length { available = parsed.content_length }
            parsed.body = __string_slice(data,end,end + available)
            while len(parsed.body) < parsed.content_length {
                now,clock_problem := std.time.monotonic_clock()
                if clock_problem.code != 0 { return request { method: _request_method(data) },http_error { code: clock_problem.code, message: "body clock" } }
                if now >= deadline { return request { method: _request_method(data) },http_error { code: 110, status: 408, message: "body timeout" } }
                remaining := (deadline - now + 999999) / 1000000
                maximum := parsed.content_length - len(parsed.body)
                if maximum > 4096 { maximum = 4096 }
                chunk,body_error := std.tcp.read_some(connection*,maximum,remaining)
                if body_error.code != 0 {
                    status := 0
                    if body_error.code == 110 { status = 408 }
                    return request { method: _request_method(data) },http_error { code: body_error.code, status: status, message: body_error.operation }
                }
                finished,finished_error := std.time.monotonic_clock()
                if finished_error.code != 0 { return request { method: _request_method(data) },http_error { code: finished_error.code, message: "body clock" } }
                if finished >= deadline { return request { method: _request_method(data) },http_error { code: 110, status: 408, message: "body timeout" } }
                if chunk.eof { return request { method: _request_method(data) },_problem(400,"truncated request body") }
                parsed.body = parsed.body + chunk.data
            }
            return parsed,http_error {}
        }
        first := _line_end(data,0)
        if first < 0 && len(data) > config.max_request_line_bytes { return request { method: _request_method(data) },_problem(414,"request line exceeded") }
        if len(data) >= config.max_header_bytes { return request { method: _request_method(data) },_problem(431,"header bytes exceeded") }
        now,now_error := std.time.monotonic_clock()
        if now_error.code != 0 { return request { method: _request_method(data) },http_error { code: now_error.code, message: "header clock" } }
        if now >= deadline { return request { method: _request_method(data) },http_error { code: 110, status: 408, message: "header timeout" } }
        remaining := (deadline - now + 999999) / 1000000
        maximum := config.max_header_bytes - len(data)
        if maximum > 1024 { maximum = 1024 }
        chunk,error := std.tcp.read_some(connection*,maximum,remaining)
        if error.code != 0 {
            status := 0
            if error.code == 110 { status = 408 }
            return request { method: _request_method(data) },http_error { code: error.code, status: status, message: error.operation }
        }
        // A ready read may complete after the deadline due to scheduler
        // suspension or poll's millisecond rounding. Never accept late headers.
        finished,finished_error := std.time.monotonic_clock()
        if finished_error.code != 0 { return request { method: _request_method(data) },http_error { code: finished_error.code, message: "header clock" } }
        if finished >= deadline { return request { method: _request_method(data) },http_error { code: 110, status: 408, message: "header timeout" } }
        if chunk.eof {
            if len(data) == 0 { return request { method: _request_method(data) },http_error { code: 0, message: "EOF" } }
            return request { method: _request_method(data) },_problem(400,"truncated request headers")
        }
        scanned = len(data) - 3
        if scanned < 0 { scanned = 0 }
        data = data + chunk.data
    }
    return request { method: _request_method(data) },_problem(400,"unreachable request state")
}
// Serializes a response and bounds the complete network write. The socket
// remains owned by the caller, which must close it on every outcome.
func write_response(std.tcp.socket* connection, response value, bool head, int timeout_ms) http_error {
    if timeout_ms < 1 || timeout_ms > 2147483647 { return _problem(0,"invalid response write timeout") }
    wire,error := serialize_response(value,head)
    if error.code != 0 { return error }
    written,problem := std.tcp.write_all(connection*,wire,timeout_ms)
    if problem.code != 0 { return http_error { code: problem.code, message: problem.operation } }
    if written != len(wire) { return http_error { code: 5, message: "short response write" } }
    return http_error {}
}
func serve_next(server* value) (exchange,http_error) {
    if value.closed { return exchange {},http_error { code: 9, message: "server closed" } }
    config := value.config
    connection,accept_error := std.tcp.accept(value.listener,config.accept_timeout_ms)
    if accept_error.code != 0 { return exchange {},http_error { code: accept_error.code, message: accept_error.operation } }
    request,read_error := _read_request(connection*,config)
    if read_error.status == 0 && read_error.message == "EOF" {
        closed := std.tcp.close(connection*)
        return exchange { peer_eof: true },http_error { code: closed.code, message: closed.operation }
    }
    if read_error.code != 0 && read_error.status == 0 {
        std.tcp.close(connection*)
        return exchange { peer_eof: true },read_error
    }
    response := route(request)
    if read_error.code != 0 { response = std.http.response { status: read_error.status, body: "{\"error\":\"request rejected\"}" } }
    head := request.method == "HEAD"
    write_error := write_response(connection*,response,head,config.write_timeout_ms)
    close_error := std.tcp.close(connection*)
    if write_error.code != 0 { return exchange { status: response.status },write_error }
    if close_error.code != 0 { return exchange { status: response.status },http_error { code: close_error.code, message: close_error.operation } }
    return exchange { status: response.status },http_error {}
}
