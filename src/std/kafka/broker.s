package std.kafka
import ("std.tcp"; "std.time")

// Single owner; do not copy a connected broker. Sequential requests only.
struct broker {
    std.tcp.socket socket
    int socket_descriptor
    string client_id
    int correlation_id
    int state
}
struct api_version { int api_key, int min_version, int max_version }

func _k_network_error(int native_code, string message) error {
    code := error_transport
    if native_code == 110 { code = error_timeout }
    return error { code: code, native_code: native_code, message: message }
}
func broker_connect(string host, int port, string client_id, int timeout_ms) (broker, error) {
    b := broker { socket_descriptor: -1 }
    if timeout_ms < 1 || timeout_ms > 2147483647 || len(client_id) > 32767 {
        return b, failure(error_invalid, "invalid broker connect arguments")
    }
    socket, problem := std.tcp.dial_ipv4(host, port, timeout_ms)
    if problem.code != 0 { return b, _k_network_error(problem.code, "Kafka connect failed") }
    b.socket = socket
    b.socket_descriptor = socket.descriptor
    b.client_id = client_id
    b.correlation_id = 1
    b.state = 2
    return b, error {}
}
func broker_close(broker* b) error {
    // State is authoritative: a zero-initialized broker never owns descriptor 0.
    if b.state != 2 { b.state = 0; b.socket_descriptor = -1; return error {} }
    socket := b.socket
    problem := std.tcp.close(socket*)
    b.socket = socket
    b.state = 0
    b.socket_descriptor = -1
    if problem.code != 0 { return _k_network_error(problem.code, "Kafka close failed") }
    return error {}
}
func _k_abort(broker* b, error problem) error {
    broker_close(b*)
    problem.fatal = true
    return problem
}
func _k_remaining(int deadline) (int, error) {
    now, problem := std.time.monotonic_clock()
    if problem.code != 0 { return 0, _k_network_error(problem.code, "Kafka clock failed") }
    if now >= deadline { return 0, _k_network_error(110, "Kafka request timeout") }
    return (deadline - now + 999999) / 1000000, error {}
}
func _k_read_exact(broker* b, int size, int deadline) (string, error) {
    output := ""
    while len(output) < size {
        remaining, clock_error := _k_remaining(deadline)
        if clock_error.code != 0 { return "", _k_abort(b*, clock_error) }
        maximum := size - len(output)
        // Bound conversion work as well as allocation per TCP read. In the seed
        // runtime, converting a large byte array can outlast a short deadline.
        if maximum > 1024 { maximum = 1024 }
        socket := b.socket
        chunk, problem := std.tcp.read_some(socket*, maximum, remaining)
        b.socket = socket
        if problem.code != 0 {
            result := _k_network_error(problem.code, "Kafka read failed")
            return "", _k_abort(b*, result)
        }
        if chunk.eof || len(chunk.data) == 0 {
            result := _k_network_error(104, "Kafka unexpected EOF")
            return "", _k_abort(b*, result)
        }
        output = output + chunk.data
        after_read, after_error := _k_remaining(deadline)
        if after_error.code != 0 { return "", _k_abort(b*, after_error) }
    }
    return output, error {}
}

// Request contains a v1 header (API key, version, next correlation, client ID).
// Obtain the next ID from b.correlation_id; it is consumed exactly once on I/O.
// Returns API body only. Flexible response headers are outside this v0 milestone.
func broker_send_request(broker* b, string request_data, int timeout_ms) (string, error) {
    if b.state != 2 { return "", failure(error_closed, "Kafka broker is closed") }
    if timeout_ms < 1 || timeout_ms > 2147483647 { return "", failure(error_invalid, "invalid Kafka timeout") }
    if len(request_data) < 10 || len(request_data) > 1048576 { return "", failure(error_bounds, "invalid Kafka request size") }
    request := new_cursor(request_data, 1048576)
    key := read_int(request*, 2)
    version := read_int(request*, 2)
    correlation := read_int(request*, 4)
    client := read_nullable(request*, 2, 32767)
    if request.failure.code != 0 || key < 0 || version < 0 || !client.present ||
        correlation < 1 || correlation > 2147483647 || correlation != b.correlation_id {
        return "", failure(error_invalid, "invalid Kafka request header or correlation")
    }
    now, clock_error := std.time.monotonic_clock()
    if clock_error.code != 0 { return "", _k_network_error(clock_error.code, "Kafka clock failed") }
    deadline := now + timeout_ms * 1000000
    w := new_writer(1048580)
    size := len(request_data)
    put_int(w*, size, 4)
    put_raw(w*, request_data)
    if w.failure.code != 0 { return "", w.failure }
    remaining, deadline_error := _k_remaining(deadline)
    if deadline_error.code != 0 { return "", deadline_error }
    b.correlation_id = correlation + 1
    if correlation == 2147483647 { b.correlation_id = 1 }
    socket := b.socket
    written, write_error := std.tcp.write_all(socket*, w.data, remaining)
    b.socket = socket
    if write_error.code != 0 {
        result := _k_network_error(write_error.code, "Kafka write failed")
        return "", _k_abort(b*, result)
    }
    if written != len(w.data) {
        result := _k_network_error(5, "Kafka incomplete write")
        return "", _k_abort(b*, result)
    }
    header, header_error := _k_read_exact(b*, 4, deadline)
    if header_error.code != 0 { return "", header_error }
    length_cursor := new_cursor(header, 4)
    length := read_int(length_cursor*, 4)
    if length < 4 {
        result := failure(error_protocol, "invalid Kafka response length")
        return "", _k_abort(b*, result)
    }
    if length > 1048576 {
        result := failure(error_bounds, "Kafka response exceeds frame limit")
        return "", _k_abort(b*, result)
    }
    response, response_error := _k_read_exact(b*, length, deadline)
    if response_error.code != 0 { return "", response_error }
    c := new_cursor(response, 1048576)
    response_correlation := read_int(c*, 4)
    if response_correlation != correlation {
        result := failure(error_protocol, "Kafka correlation mismatch")
        return "", _k_abort(b*, result)
    }
    body := take(c*, length - 4)
    after_body, body_timeout := _k_remaining(deadline)
    if body_timeout.code != 0 { return "", _k_abort(b*, body_timeout) }
    return body, error {}
}

func broker_api_versions(broker* b, int timeout_ms) (api_version[], error) {
    empty := api_version[]()
    request := broker_build_api_versions_request(b.client_id, b.correlation_id)
    body, problem := broker_send_request(b*, request, timeout_ms)
    if problem.code != 0 { return empty, problem }
    versions, parse_error := broker_parse_api_versions_response(body)
    if parse_error.code != 0 && parse_error.code != error_broker { return empty, _k_abort(b*, parse_error) }
    return versions, parse_error
}
// Request header v1, API 18 version 0. Invalid inputs produce no request.
func broker_build_api_versions_request(string client_id, int correlation_id) string {
    if len(client_id) > 32767 || correlation_id < 1 || correlation_id > 2147483647 { return "" }
    w := new_writer(1048576)
    put_int(w*, 18, 2)
    put_int(w*, 0, 2)
    put_int(w*, correlation_id, 4)
    put_string(w*, client_id)
    return w.data
}

// Accepts the API body only; broker_send_request validates/strips correlation.
func broker_parse_api_versions_response(string response_data) (api_version[], error) {
    versions := api_version[]()
    c := new_cursor(response_data, 1048576)
    status := read_int(c*, 2)
    count := read_int(c*, 4)
    if c.failure.code != 0 { return versions, c.failure }
    if count < 0 || count > 4096 { return versions, failure(error_protocol, "invalid API version count") }
    if count > (len(response_data) - c.position) / 6 { return versions, failure(error_protocol, "truncated API versions") }
    i := 0
    while i < count {
        key := read_int(c*, 2)
        minimum := read_int(c*, 2)
        maximum := read_int(c*, 2)
        if key < 0 || minimum < 0 || maximum < minimum { return versions, failure(error_protocol, "invalid API version range") }
        j := 0
        while j < len(versions) {
            if versions[j].api_key == key { return versions, failure(error_protocol, "duplicate API key") }
            j = j + 1
        }
        versions = append(versions, api_version { api_key: key, min_version: minimum, max_version: maximum })
        i = i + 1
    }
    problem := finished(c*)
    if problem.code != 0 { return versions, problem }
    if status != 0 {
        return versions, error { code: error_broker, native_code: status, message: "ApiVersions broker error" }
    }
    return versions, error {}
}
