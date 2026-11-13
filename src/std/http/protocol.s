package std.http
import "std.prelude"
extern "intrinsic" func __host_byte_at(string text, int index) int
extern "intrinsic" func __string_slice(string text, int start, int end) string
extern "intrinsic" func __std_byte_string(int value) string

func _token(int byte) bool {
    if (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) { return true }
    return byte == 33 || byte == 35 || byte == 36 || byte == 37 || byte == 38 || byte == 39 || byte == 42 || byte == 43 || byte == 45 || byte == 46 || byte == 94 || byte == 95 || byte == 96 || byte == 124 || byte == 126
}
func _hex(int byte) bool { return (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 70) || (byte >= 97 && byte <= 102) }
func _lower(string text) string {
    result := ""
    index := 0
    while index < len(text) {
        byte := __host_byte_at(text,index)
        if byte >= 65 && byte <= 90 { byte = byte + 32 }
        result = result + __std_byte_string(byte)
        index = index + 1
    }
    return result
}
func _trim(string text) string {
    start := 0
    end := len(text)
    while start < end && (__host_byte_at(text,start) == 32 || __host_byte_at(text,start) == 9) { start = start + 1 }
    while end > start && (__host_byte_at(text,end - 1) == 32 || __host_byte_at(text,end - 1) == 9) { end = end - 1 }
    return __string_slice(text,start,end)
}
// -1 means incomplete, -2 malformed line endings. Only inspect header bytes;
// surplus bytes belong to a body/pipeline and are never reused on this slice.
func _header_end_from(string text, int start) int {
    index := start
    while index < len(text) {
        byte := __host_byte_at(text,index)
        if byte == 10 && (index == 0 || __host_byte_at(text,index - 1) != 13) { return -2 }
        if byte == 13 && index + 1 < len(text) && __host_byte_at(text,index + 1) != 10 { return -2 }
        if byte == 10 && index >= 3 && __host_byte_at(text,index - 1) == 13 && __host_byte_at(text,index - 2) == 10 && __host_byte_at(text,index - 3) == 13 { return index + 1 }
        index = index + 1
    }
    return -1
}
func _header_end(string text) int { return _header_end_from(text,0) }
func _line_end(string text, int start) int {
    index := start
    while index + 1 < len(text) {
        if __host_byte_at(text,index) == 13 && __host_byte_at(text,index + 1) == 10 { return index }
        index = index + 1
    }
    return -1
}
func _host(string host) bool {
    // This IPv4/hostname slice deliberately rejects IPv6 authorities and
    // escaped/sub-delimiter reg-names rather than accepting malformed syntax.
    if len(host) == 0 { return false }
    index := 0
    while index < len(host) && __host_byte_at(host,index) != 58 {
        byte := __host_byte_at(host,index)
        if !((byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || byte == 45 || byte == 46 || byte == 95) { return false }
        index = index + 1
    }
    if index == 0 { return false }
    if index == len(host) { return true }
    index = index + 1
    if index == len(host) { return false }
    port := 0
    while index < len(host) {
        byte := __host_byte_at(host,index)
        if byte < 48 || byte > 57 { return false }
        port = port * 10 + byte - 48
        if port > 65535 { return false }
        index = index + 1
    }
    return true
}
func parse_request(string raw, options requested) (request,http_error) {
    config,config_error := _options(requested)
    if config_error.code != 0 { return request {},config_error }
    end := _header_end(raw)
    if end == -2 { return request {},_problem(400,"invalid CRLF framing") }
    if end < 0 { return request {},_problem(400,"incomplete request headers") }
    if end > config.max_header_bytes { return request {},_problem(431,"header bytes exceeded") }
    first := _line_end(raw,0)
    if first < 0 { return request {},_problem(400,"missing request line") }
    if first > config.max_request_line_bytes { return request {},_problem(414,"request line exceeded") }
    method_end := 0
    while method_end < first && __host_byte_at(raw,method_end) != 32 {
        if !_token(__host_byte_at(raw,method_end)) { return request {},_problem(400,"invalid method token") }
        method_end = method_end + 1
    }
    if method_end == 0 || method_end >= first { return request {},_problem(400,"invalid request line") }
    target_end := method_end + 1
    while target_end < first && __host_byte_at(raw,target_end) != 32 { target_end = target_end + 1 }
    if target_end == method_end + 1 || target_end >= first { return request {},_problem(400,"invalid request target") }
    version := __string_slice(raw,target_end + 1,first)
    if version != "HTTP/1.1" { return request {},_problem(505,"unsupported HTTP version") }
    target := __string_slice(raw,method_end + 1,target_end)
    if __host_byte_at(target,0) != 47 { return request {},_problem(400,"origin-form target required") }
    path_end := len(target)
    index := 0
    while index < len(target) {
        byte := __host_byte_at(target,index)
        if byte <= 32 || byte >= 127 || byte == 35 { return request {},_problem(400,"invalid request target") }
        if byte == 63 && path_end == len(target) { path_end = index }
        if byte == 37 {
            if index + 2 >= len(target) { return request {},_problem(400,"invalid percent escape") }
            if !_hex(__host_byte_at(target,index + 1)) || !_hex(__host_byte_at(target,index + 2)) { return request {},_problem(400,"invalid percent escape") }
            index = index + 2
        }
        index = index + 1
    }
    result := request { method: __string_slice(raw,0,method_end), target: target, path: __string_slice(target,0,path_end) }
    result.header_bytes = end
    if path_end < len(target) { result.query = __string_slice(target,path_end + 1,len(target)) }
    position := first + 2
    count := 0
    hosts := 0
    lengths := 0
    body := false
    body_length := 0
    content_types := 0
    transfer := false
    expect := false
    while position < end - 2 {
        line_end := _line_end(raw,position)
        if line_end < position { return request {},_problem(400,"invalid header") }
        count = count + 1
        if count > config.max_headers { return request {},_problem(431,"header count exceeded") }
        colon := position
        while colon < line_end && __host_byte_at(raw,colon) != 58 {
            if !_token(__host_byte_at(raw,colon)) { return request {},_problem(400,"invalid header name") }
            colon = colon + 1
        }
        if colon == position || colon == line_end { return request {},_problem(400,"invalid header name") }
        index = colon + 1
        while index < line_end {
            byte := __host_byte_at(raw,index)
            if (byte < 32 && byte != 9) || byte == 127 { return request {},_problem(400,"invalid header value") }
            index = index + 1
        }
        name := _lower(__string_slice(raw,position,colon))
        value := _trim(__string_slice(raw,colon + 1,line_end))
        result.headers = append(result.headers,header { name: name, value: value })
        if name == "content-type" {
            content_types = content_types + 1
            if content_types > 1 { return request {},_problem(400,"duplicate Content-Type") }
        }
        if name == "host" {
            hosts = hosts + 1
            if hosts > 1 || !_host(value) { return request {},_problem(400,"invalid Host") }
            result.host = value
        }
        if name == "content-length" {
            lengths = lengths + 1
            if lengths > 1 || len(value) == 0 { return request {},_problem(400,"invalid Content-Length") }
            index = 0
            while index < len(value) {
                byte := __host_byte_at(value,index)
                if byte < 48 || byte > 57 { return request {},_problem(400,"invalid Content-Length") }
                if byte != 48 { body = true }
                if body_length > config.max_body_bytes / 10 || (body_length == config.max_body_bytes / 10 && byte - 48 > config.max_body_bytes % 10) { return request {},_problem(413,"request body exceeded") }
                body_length = body_length * 10 + byte - 48
                index = index + 1
            }
        }
        if name == "transfer-encoding" { transfer = true }
        if name == "expect" { expect = true }
        position = line_end + 2
    }
    if hosts != 1 { return request {},_problem(400,"Host required") }
    if transfer && lengths != 0 { return request {},_problem(400,"ambiguous request framing") }
    if transfer { return request {},_problem(501,"transfer coding not supported in this slice") }
    if expect { return request {},_problem(417,"expectation not supported") }
    if body && config.max_body_bytes == 0 { return request {},_problem(413,"request body not supported in this slice") }
    result.content_length = body_length
    return result,http_error {}
}
func _reason(int status) string {
    if status == 200 { return "OK" }
    if status == 400 { return "Bad Request" }
    if status == 404 { return "Not Found" }
    if status == 201 { return "Created" }
    if status == 204 { return "No Content" }
    if status == 409 { return "Conflict" }
    if status == 415 { return "Unsupported Media Type" }
    if status == 500 { return "Internal Server Error" }
    if status == 405 { return "Method Not Allowed" }
    if status == 408 { return "Request Timeout" }
    if status == 413 { return "Content Too Large" }
    if status == 414 { return "URI Too Long" }
    if status == 417 { return "Expectation Failed" }
    if status == 431 { return "Request Header Fields Too Large" }
    if status == 501 { return "Not Implemented" }
    if status == 505 { return "HTTP Version Not Supported" }
    return ""
}
func header_value(request value, string name) string {
    wanted := _lower(name)
    index := 0
    while index < len(value.headers) {
        if value.headers[index].name == wanted { return value.headers[index].value }
        index = index + 1
    }
    return ""
}
func _safe_header(string name, string value) bool {
    if len(name) == 0 { return false }
    index := 0
    while index < len(name) {
        if !_token(__host_byte_at(name,index)) { return false }
        index = index + 1
    }
    index = 0
    while index < len(value) {
        byte := __host_byte_at(value,index)
        if (byte < 32 && byte != 9) || byte == 127 { return false }
        index = index + 1
    }
    return true
}
func serialize_response(response value, bool head) (string,http_error) {
    reason := _reason(value.status)
    if reason == "" { return "",_problem(0,"unsupported response status") }
    if value.status == 204 {
        if value.body != "" || len(value.headers) != 0 { return "",_problem(0,"204 response cannot contain body or custom headers") }
        return "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n",http_error {}
    }
    content_type := value.content_type
    if content_type == "" { content_type = "application/json" }
    if !_safe_header("Content-Type",content_type) { return "",_problem(0,"invalid Content-Type") }
    wire := "HTTP/1.1 " + std.prelude.to_string(value.status) + " " + reason + "\r\nContent-Type: " + content_type + "\r\nContent-Length: " + std.prelude.to_string(len(value.body)) + "\r\nConnection: close\r\n"
    index := 0
    has_allow := false
    while index < len(value.headers) {
        item := value.headers[index]
        name := _lower(item.name)
        if !_safe_header(item.name,item.value) || name == "content-length" || name == "transfer-encoding" || name == "connection" || name == "content-type" { return "",_problem(0,"invalid or reserved response header") }
        if name == "allow" { has_allow = true }
        wire = wire + item.name + ": " + item.value + "\r\n"
        index = index + 1
    }
    if value.status == 405 && !has_allow { wire = wire + "Allow: GET, HEAD\r\n" }
    wire = wire + "\r\n"
    if !head { wire = wire + value.body }
    return wire,http_error {}
}
func route(request value) response {
    if value.path != "/health" { return response { status: 404, body: "{\"error\":\"not found\"}" } }
    if value.method != "GET" && value.method != "HEAD" { return response { status: 405, body: "{\"error\":\"method not allowed\"}" } }
    return response { status: 200, body: "{\"status\":\"ok\"}" }
}
