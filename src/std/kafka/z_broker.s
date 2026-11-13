package std.kafka

import ("std.tcp"; "std.result"; "std.time")

// Kafka broker connection and protocol negotiation
struct broker_error {
    int code
    string message
}

struct broker {
    std.tcp.socket connection
    string client_id
    int correlation_id
}

struct api_version {
    int api_key
    int min_version
    int max_version
}

struct cursor {
    string data
    int position
}

// Connect to a Kafka broker
func connect_broker(string host, int port, string client_id, int timeout_ms) (broker, broker_error) {
    socket, tcp_err := std.tcp.dial_ipv4(host, port, timeout_ms)
    if tcp_err.code != 0 {
        return broker { connection: socket }, broker_error { 
            code: tcp_err.code,
            message: "tcp connect: " + tcp_err.operation
        }
    }
    
    return broker {
        connection: socket,
        client_id: client_id,
        correlation_id: 1
    }, broker_error { code: 0 }
}

// Send a raw Kafka request and receive response
// Handles framing: 4-byte size prefix followed by request data
func send_request(broker* b, string request_data, int timeout_ms) (string, broker_error) {
    if b.connection.closed {
        return "", broker_error { code: -1, message: "connection closed" }
    }
    
    // Build frame: 4-byte size + request data
    size := len(request_data)
    size_bytes := make([]int, 4)
    size_bytes[0] = (size >> 24) & 0xff
    size_bytes[1] = (size >> 16) & 0xff
    size_bytes[2] = (size >> 8) & 0xff
    size_bytes[3] = size & 0xff
    
    frame := ""
    i := 0
    while i < 4 {
        frame = frame + __std_byte_string(size_bytes[i])
        i = i + 1
    }
    frame = frame + request_data
    
    // Send the entire frame
    _, write_err := std.tcp.write_all(&b.connection, frame, timeout_ms)
    if write_err.code != 0 {
        return "", broker_error {
            code: write_err.code,
            message: "tcp write: " + write_err.operation
        }
    }
    
    // Read response size (4 bytes)
    size_data, read_err := std.tcp.read_some(&b.connection, 4, timeout_ms)
    if read_err.code != 0 {
        return "", broker_error {
            code: read_err.code,
            message: "tcp read size: " + read_err.operation
        }
    }
    
    if len(size_data.data) != 4 {
        return "", broker_error { code: -1, message: "incomplete response size" }
    }
    
    // Parse response size (big-endian)
    response_size := 0
    i = 0
    while i < 4 {
        response_size = response_size * 256 + __host_byte_at(size_data.data, i)
        i = i + 1
    }
    
    if response_size < 0 || response_size > 1048576 {
        return "", broker_error { code: -1, message: "invalid response size" }
    }
    
    // Read response data
    response_data, read_err := std.tcp.read_some(&b.connection, response_size, timeout_ms)
    if read_err.code != 0 {
        return "", broker_error {
            code: read_err.code,
            message: "tcp read data: " + read_err.operation
        }
    }
    
    return response_data.data, broker_error { code: 0 }
}

// Close broker connection
func close_broker(broker* b) broker_error {
    tcp_err := std.tcp.close(&b.connection)
    if tcp_err.code != 0 {
        return broker_error {
            code: tcp_err.code,
            message: "tcp close: " + tcp_err.operation
        }
    }
    return broker_error { code: 0 }
}

// Build ApiVersions request
// Format: api_key(2) + version(2) + correlation_id(4) + client_id_string
func build_api_versions_request(string client_id, int correlation_id) string {
    return _put_int16(18) + _put_int16(0) + _put_int32(correlation_id) + _put_string(client_id)
}

// Parse ApiVersions response
// Format: error_code(2) + api_versions[] + throttle_time(4, v1+)
func parse_api_versions_response(string response_data) (api_version[], broker_error) {
    c := cursor { data: response_data, position: 0 }
    
    // Read error code
    error_code, err1 := _read_int16(&c)
    if err1.code != 0 {
        return make([]api_version, 0), broker_error { code: err1.code, message: "read error code" }
    }
    
    if error_code != 0 {
        return make([]api_version, 0), broker_error { code: error_code, message: "broker returned error" }
    }
    
    // Read number of API versions
    count, err2 := _read_int32(&c)
    if err2.code != 0 {
        return make([]api_version, 0), broker_error { code: err2.code, message: "read api version count" }
    }
    
    if count < 0 || count > 256 {
        return make([]api_version, 0), broker_error { code: -1, message: "invalid api version count" }
    }
    
    versions := make([]api_version, count)
    i := 0
    while i < count {
        api_key, err3 := _read_int16(&c)
        if err3.code != 0 {
            return make([]api_version, 0), broker_error { code: err3.code, message: "read api key" }
        }
        
        min_ver, err4 := _read_int16(&c)
        if err4.code != 0 {
            return make([]api_version, 0), broker_error { code: err4.code, message: "read min version" }
        }
        
        max_ver, err5 := _read_int16(&c)
        if err5.code != 0 {
            return make([]api_version, 0), broker_error { code: err5.code, message: "read max version" }
        }
        
        versions[i] = api_version {
            api_key: api_key,
            min_version: min_ver,
            max_version: max_ver
        }
        
        i = i + 1
    }
    
    return versions, broker_error { code: 0 }
}

// Helper: put 16-bit big-endian integer as string
func _put_int16(int value) string {
    high := (value >> 8) & 0xff
    low := value & 0xff
    return __std_byte_string(high) + __std_byte_string(low)
}

// Helper: put 32-bit big-endian integer as string
func _put_int32(int value) string {
    b3 := (value >> 24) & 0xff
    b2 := (value >> 16) & 0xff
    b1 := (value >> 8) & 0xff
    b0 := value & 0xff
    return __std_byte_string(b3) + __std_byte_string(b2) + __std_byte_string(b1) + __std_byte_string(b0)
}

// Helper: put string with 2-byte length prefix (Kafka string type)
func _put_string(string value) string {
    length := len(value)
    return _put_int16(length) + value
}

// Helper: read 16-bit big-endian integer
func _read_int16(cursor* c) (int, broker_error) {
    if c.position + 2 > len(c.data) {
        return 0, broker_error { code: 1, message: "underrun" }
    }
    
    high := __host_byte_at(c.data, c.position)
    low := __host_byte_at(c.data, c.position + 1)
    c.position = c.position + 2
    
    return high * 256 + low, broker_error { code: 0 }
}

// Helper: read 32-bit big-endian integer
func _read_int32(cursor* c) (int, broker_error) {
    if c.position + 4 > len(c.data) {
        return 0, broker_error { code: 1, message: "underrun" }
    }
    
    b3 := __host_byte_at(c.data, c.position)
    b2 := __host_byte_at(c.data, c.position + 1)
    b1 := __host_byte_at(c.data, c.position + 2)
    b0 := __host_byte_at(c.data, c.position + 3)
    c.position = c.position + 4
    
    return b3 * 16777216 + b2 * 65536 + b1 * 256 + b0, broker_error { code: 0 }
}

// Helper: read string with 2-byte length prefix
func _read_string(cursor* c) (string, broker_error) {
    length, err := _read_int16(c)
    if err.code != 0 {
        return "", err
    }
    
    if length < 0 || length > 10000 {
        return "", broker_error { code: 1, message: "invalid string length" }
    }
    
    if c.position + length > len(c.data) {
        return "", broker_error { code: 1, message: "underrun" }
    }
    
    str_data := __string_slice(c.data, c.position, c.position + length)
    c.position = c.position + length
    return str_data, broker_error { code: 0 }
}

// Intrinsic functions
extern "intrinsic" func __host_byte_at(string text, int index) int
extern "intrinsic" func __std_byte_string(int value) string
extern "intrinsic" func __string_slice(string text, int start, int end) string

