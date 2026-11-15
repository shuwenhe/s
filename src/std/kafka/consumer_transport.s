package std.kafka
import ("std.tcp"; "std.time")

// Exactly one socket owner and one pending exchange, resumable across poll calls.
struct consumer_link {
    broker connection
    api_version[] versions
    string peer_host
    int peer_port
    bool negotiating
    string outgoing
    int write_position
    string size_header
    string body
    string[] body_fragments
    int body_received
    int response_size
    int correlation
    int deadline_ns
    int state
    error problem
}
func consumer_link_open(string host, int port, string client_id, int timeout_ms) (consumer_link, error) {
    link := consumer_link {}
    b, problem := broker_connect(host, port, client_id, timeout_ms)
    if problem.code != 0 { return link, problem }
    versions, negotiation := broker_api_versions(b*, timeout_ms)
    if negotiation.code != 0 { broker_close(b*); return link, negotiation }
    link.connection = b
    link.versions = versions
    link.peer_host = host
    link.peer_port = port
    return link, error {}
}
func consumer_link_close(consumer_link* link) error {
    b := link.connection
    problem := broker_close(b*)
    link.connection = b
    link.versions = api_version[]()
    link.peer_host = ""
    link.peer_port = 0
    link.negotiating = false
    link.outgoing = ""
    link.write_position = 0
    link.size_header = ""
    link.body = ""
    link.body_fragments = string[]()
    link.body_received = 0
    link.response_size = 0
    link.correlation = 0
    link.deadline_ns = 0
    link.state = 0
    link.problem = error {}
    return problem
}
func consumer_supports(api_version[] versions, int key, int version) bool {
    i := 0
    while i < len(versions) {
        v := versions[i]
        if v.api_key == key { return v.min_version <= version && v.max_version >= version }
        i = i + 1
    }
    return false
}
func _kc_link_fail(consumer_link* link, error problem) {
    consumer_link_close(link*)
    problem.fatal = true
    link.problem = problem
    link.state = 4
}
func _kc_link_error(consumer_link* link, int code, string text) {
    problem := failure(code, text)
    _kc_link_fail(link*, problem)
}
func consumer_exchange_begin(consumer_link* link, string data, int timeout_ms) error {
    b := link.connection
    if b.state != 2 { return failure(error_closed, "consumer connection closed") }
    if link.state > 0 && link.state < 4 { return failure(error_invalid, "consumer exchange already pending") }
    if timeout_ms < 1 || timeout_ms > 2147483647 { return failure(error_invalid, "invalid consumer request timeout") }
    if len(data) < 10 || len(data) > 1048576 { return failure(error_bounds, "consumer request size") }
    c := new_cursor(data, 1048576)
    api := read_int(c*, 2)
    version := read_int(c*, 2)
    correlation := read_int(c*, 4)
    client := read_nullable(c*, 2, 32767)
    if c.failure.code != 0 || api < 0 || version < 0 || !client.present || correlation != b.correlation_id || correlation < 1 {
        return failure(error_invalid, "consumer request correlation/header")
    }
    now, problem := std.time.monotonic_clock()
    if problem.code != 0 { return _k_network_error(problem.code, "consumer clock") }
    w := new_writer(1048580)
    size := len(data)
    put_int(w*, size, 4)
    put_raw(w*, data)
    link.outgoing = w.data
    link.write_position = 0
    link.size_header = ""
    link.body = ""
    link.body_fragments = string[]()
    link.body_received = 0
    link.response_size = 0
    link.correlation = correlation
    link.deadline_ns = now + timeout_ms * 1000000
    link.problem = error {}
    link.state = 1
    return error {}
}
// One I/O step, at most slice_ms (0..10); total request deadline is separate.
func consumer_exchange_step(consumer_link* link, int slice_ms) error {
    if link.state == 0 || link.state == 4 { return link.problem }
    if slice_ms < 0 || slice_ms > 10 { return failure(error_invalid, "consumer step slice must be 0..10 ms") }
    now, clock_error := std.time.monotonic_clock()
    if clock_error.code != 0 { return _k_network_error(clock_error.code, "consumer clock") }
    if now >= link.deadline_ns {
        problem := _k_network_error(110, "consumer request timeout")
        _kc_link_fail(link*, problem)
        return link.problem
    }
    remaining := (link.deadline_ns - now + 999999) / 1000000
    wait_ms := slice_ms
    if wait_ms > remaining { wait_ms = remaining }
    b := link.connection
    socket := b.socket
    if link.state == 1 {
        if link.write_position == 0 {
            b.correlation_id = b.correlation_id + 1
            if b.correlation_id > 2147483647 { b.correlation_id = 1 }
        }
        // Mark ID consumed even if first nonblocking write makes no progress.
        link.state = 2
    }
    if link.state == 2 {
        count, problem := std.tcp.write_some(socket, link.outgoing, link.write_position, wait_ms)
        if problem.code == 11 || problem.code == 110 { link.connection = b; return error {} }
        if problem.code != 0 || count == 0 {
            code := problem.code
            if code == 0 { code = 5 }
            issue := _k_network_error(code, "consumer write")
            link.connection = b
            _kc_link_fail(link*, issue)
            return link.problem
        }
        link.write_position = link.write_position + count
        link.connection = b
        if link.write_position == len(link.outgoing) { link.outgoing = ""; link.state = 3 }
        return error {}
    }
    maximum := 4 - len(link.size_header)
    if link.response_size != 0 { maximum = link.response_size - link.body_received }
    if maximum > 1024 { maximum = 1024 }
    chunk, problem := std.tcp.read_some(socket*, maximum, wait_ms)
    b.socket = socket
    link.connection = b
    if problem.code == 11 || problem.code == 110 { return error {} }
    if problem.code != 0 || chunk.eof || len(chunk.data) == 0 {
        code := problem.code
        if code == 0 { code = 104 }
        issue := _k_network_error(code, "consumer read/EOF")
        _kc_link_fail(link*, issue)
        return link.problem
    }
    if link.response_size == 0 {
        link.size_header = link.size_header + chunk.data
        if len(link.size_header) == 4 {
            c := new_cursor(link.size_header, 4)
            size := read_int(c*, 4)
            if size < 4 { _kc_link_error(link*, error_protocol, "consumer response length"); return link.problem }
            if size > 1048576 { _kc_link_error(link*, error_bounds, "consumer response frame cap"); return link.problem }
            link.response_size = size
        }
    } else {
        _kc_body_append(link*, chunk.data)
        if link.body_received == link.response_size {
            link.body = _kc_body_collect(link.body_fragments)
            link.body_fragments = string[]()
            c := new_cursor(link.body, 1048576)
            correlation := read_int(c*, 4)
            if correlation != link.correlation { _kc_link_error(link*, error_protocol, "consumer correlation mismatch"); return link.problem }
            size := len(link.body) - 4
            link.body = take(c*, size)
            link.state = 4
        }
    }
    after, after_error := std.time.monotonic_clock()
    if after_error.code != 0 || after >= link.deadline_ns {
        issue := _k_network_error(110, "consumer decode/read timeout")
        _kc_link_fail(link*, issue)
    }
    return link.problem
}
func _kc_header(string client, int correlation, int api, int version) writer {
    w := new_writer(1048576)
    put_int(w*, api, 2)
    put_int(w*, version, 2)
    put_int(w*, correlation, 4)
    put_string(w*, client)
    return w
}
func _kc_broker_error(int status, string context) error {
    if status == 0 { return error {} }
    return error { code: error_broker, native_code: status, message: context }
}

// Binary carry keeps fragment depth logarithmic, including under Seed's rope
// strings. A 1 MiB frame needs at most 21 levels even with one-byte reads.
func _kc_body_append(consumer_link* link, string data) {
    part := data
    levels := link.body_fragments
    index := 0
    while index < len(levels) {
        prior := levels[index]
        if len(prior) == 0 { break }
        part = prior + part
        levels[index] = ""
        index = index + 1
    }
    if index == len(levels) { levels = append(levels, part) }
    else { levels[index] = part }
    link.body_fragments = levels
    link.body_received = link.body_received + len(data)
}
func _kc_body_collect(string[] levels) string {
    result := ""
    index := len(levels) - 1
    while index >= 0 {
        if len(levels[index]) > 0 { result = result + levels[index] }
        index = index - 1
    }
    return result
}
