package std.kafka

import ("std.tcp")

struct broker {
    int socket_descriptor
    string client_id
    int correlation_id
    int state
}

struct api_version {
    int api_key
    int min_version
    int max_version
}

// Connect to Kafka broker
// Returns broker handle and error
func broker_connect(string host, int port, string client_id, int timeout_ms) (broker, error) {
    socket, tcp_err := std.tcp.dial_ipv4(host, port, timeout_ms)
    
    var b broker
    var result_err error
    
    if tcp_err.code != 0 {
        b.socket_descriptor = -1
        b.state = 0
        result_err.code = tcp_err.code
        result_err.message = "tcp connect failed"
        return b, result_err
    }
    
    b.socket_descriptor = socket.descriptor
    b.client_id = client_id
    b.correlation_id = 1
    b.state = 2
    result_err.code = 0
    return b, result_err
}

// Send request and read response
// Handles Kafka framing: [int32 size][payload]
func broker_send_request(broker* b, string request_data, int timeout_ms) (string, error) {
    var empty_response string = ""
    var err_response error
    
    if b.state != 2 {
        err_response.code = -1
        err_response.message = "broker not connected"
        return empty_response, err_response
    }
    
    // Build frame: 4-byte size prefix (big-endian)
    frame_size := len(request_data)
    size_bytes := _put_int32(frame_size)
    frame := size_bytes + request_data
    
    // Send request
    // Note: Can't use &std.tcp.socket directly due to compiler limitation
    // Would need to reconstruct socket from descriptor, but tcp module doesn't expose that
    // This is a workaround - we'll need the tcp module to support sending by descriptor
    // For now, return placeholder error
    var err error
    err.code = -1
    err.message = "broker.send_request: need tcp module integration"
    return empty_response, err
}

// Close connection
func broker_close(broker* b) error {
    var result_err error
    if b.state == 0 {
        result_err.code = 0
        return result_err
    }
    
    b.state = 0
    b.socket_descriptor = -1
    result_err.code = 0
    return result_err
}

// Build ApiVersions request (API key 18)
func broker_build_api_versions_request(string client_id, int correlation_id) string {
    api_key := 18
    version := 0
    
    request := ""
    request = request + _put_int16(api_key)
    request = request + _put_int16(version)
    request = request + _put_int32(correlation_id)
    request = request + _put_string(client_id)
    
    return request
}

// Parse ApiVersions response
func broker_parse_api_versions_response(string response_data) (api_version[], error) {
    var empty_versions api_version[]
    empty_versions = make([]api_version, 0)
    
    var c cursor
    c.data = response_data
    c.position = 0
    
    // Read error code (int16)
    error_code, err1 := _read_int16(&c)
    if err1.code != 0 {
        var result_err error
        result_err.code = err1.code
        result_err.message = "read error code failed"
        return empty_versions, result_err
    }
    
    if error_code != 0 {
        var result_err error
        result_err.code = error_code
        result_err.message = "broker returned error"
        return empty_versions, result_err
    }
    
    // Read number of API versions (int32)
    count, err2 := _read_int32(&c)
    if err2.code != 0 {
        var result_err error
        result_err.code = err2.code
        result_err.message = "read version count failed"
        return empty_versions, result_err
    }
    
    if count < 0 || count > 256 {
        var result_err error
        result_err.code = 1
        result_err.message = "invalid version count"
        return empty_versions, result_err
    }
    
    // Read array of API versions
    versions := make([]api_version, count)
    i := 0
    while i < count {
        api_key, err_k := _read_int16(&c)
        if err_k.code != 0 {
            var result_err error
            result_err.code = err_k.code
            result_err.message = "read api key failed"
            return empty_versions, result_err
        }
        
        min_ver, err_min := _read_int16(&c)
        if err_min.code != 0 {
            var result_err error
            result_err.code = err_min.code
            result_err.message = "read min version failed"
            return empty_versions, result_err
        }
        
        max_ver, err_max := _read_int16(&c)
        if err_max.code != 0 {
            var result_err error
            result_err.code = err_max.code
            result_err.message = "read max version failed"
            return empty_versions, result_err
        }
        
        var av api_version
        av.api_key = api_key
        av.min_version = min_ver
        av.max_version = max_ver
        versions[i] = av
        
        i = i + 1
    }
    
    var ok_err error
    ok_err.code = 0
    return versions, ok_err
}

// Helper: Encode 16-bit big-endian integer as string
func _put_int16(int value) string {
    high := (value >> 8) & 0xff
    low := value & 0xff
    return __std_byte_string(high) + __std_byte_string(low)
}

// Helper: Encode 32-bit big-endian integer as string
func _put_int32(int value) string {
    b3 := (value >> 24) & 0xff
    b2 := (value >> 16) & 0xff
    b1 := (value >> 8) & 0xff
    b0 := value & 0xff
    return __std_byte_string(b3) + __std_byte_string(b2) + __std_byte_string(b1) + __std_byte_string(b0)
}

// Helper: Encode string with 16-bit length prefix
func _put_string(string value) string {
    length := len(value)
    return _put_int16(length) + value
}

// Helper: Decode 16-bit big-endian integer from cursor
func _read_int16(cursor* c) (int, error) {
    if c.position + 2 > len(c.data) {
        var zero_val int = 0
        var err error
        err.code = 1
        err.message = "buffer underrun"
        return zero_val, err
    }
    
    high := __host_byte_at(c.data, c.position)
    low := __host_byte_at(c.data, c.position + 1)
    c.position = c.position + 2
    
    result := high * 256 + low
    var ok_err error
    ok_err.code = 0
    return result, ok_err
}

// Helper: Decode 32-bit big-endian integer from cursor
func _read_int32(cursor* c) (int, error) {
    if c.position + 4 > len(c.data) {
        var zero_val int = 0
        var err error
        err.code = 1
        err.message = "buffer underrun"
        return zero_val, err
    }
    
    b3 := __host_byte_at(c.data, c.position)
    b2 := __host_byte_at(c.data, c.position + 1)
    b1 := __host_byte_at(c.data, c.position + 2)
    b0 := __host_byte_at(c.data, c.position + 3)
    c.position = c.position + 4
    
    result := b3 * 16777216 + b2 * 65536 + b1 * 256 + b0
    var ok_err error
    ok_err.code = 0
    return result, ok_err
}

// Helper: Decode string with 16-bit length prefix from cursor
func _read_string(cursor* c) (string, error) {
    length, err_len := _read_int16(c)
    if err_len.code != 0 {
        var empty_str string = ""
        return empty_str, err_len
    }
    
    if length < 0 || length > 10000 {
        var empty_str string = ""
        var err error
        err.code = 1
        err.message = "invalid string length"
        return empty_str, err
    }
    
    if c.position + length > len(c.data) {
        var empty_str string = ""
        var err error
        err.code = 1
        err.message = "buffer underrun"
        return empty_str, err
    }
    
    str_data := __string_slice(c.data, c.position, c.position + length)
    c.position = c.position + length
    var ok_err error
    ok_err.code = 0
    return str_data, ok_err
}

extern "intrinsic" func __host_byte_at(string text, int index) int
extern "intrinsic" func __std_byte_string(int value) string
extern "intrinsic" func __string_slice(string text, int start, int end) string
