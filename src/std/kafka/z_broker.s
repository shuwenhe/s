package std.kafka

import ("std.tcp")

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

func connect_broker(string host, int port, string client_id, int timeout_ms) (broker, error) {
    var sock std.tcp.socket
    var tcp_err std.tcp.error
    sock, tcp_err = std.tcp.dial_ipv4(host, port, timeout_ms)
    if tcp_err.code != 0 {
        var empty_broker broker
        var result_err error
        result_err.code = tcp_err.code
        result_err.message = "tcp connect: " + tcp_err.operation
        return empty_broker, result_err
    }
    
    var b broker
    b.connection = sock
    b.client_id = client_id
    b.correlation_id = 1
    var ok_err error
    ok_err.code = 0
    return b, ok_err
}

func send_request(broker* b, string request_data, int timeout_ms) (string, error) {
    if b.connection.closed {
        var empty_result string = ""
        var err error
        err.code = -1
        err.message = "connection closed"
        return empty_result, err
    }
    
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
    
    _, write_err := std.tcp.write_all(&b.connection, frame, timeout_ms)
    if write_err.code != 0 {
        var empty_result string = ""
        var err error
        err.code = write_err.code
        err.message = "tcp write: " + write_err.operation
        return empty_result, err
    }
    
    size_data, read_err := std.tcp.read_some(&b.connection, 4, timeout_ms)
    if read_err.code != 0 {
        var empty_result string = ""
        var err error
        err.code = read_err.code
        err.message = "tcp read size: " + read_err.operation
        return empty_result, err
    }
    
    if len(size_data.data) != 4 {
        var empty_result string = ""
        var err error
        err.code = -1
        err.message = "incomplete response size"
        return empty_result, err
    }
    
    response_size := 0
    i = 0
    while i < 4 {
        response_size = response_size * 256 + __host_byte_at(size_data.data, i)
        i = i + 1
    }
    
    if response_size < 0 || response_size > 1048576 {
        var empty_result string = ""
        var err error
        err.code = -1
        err.message = "invalid response size"
        return empty_result, err
    }
    
    response_data, read_err = std.tcp.read_some(&b.connection, response_size, timeout_ms)
    if read_err.code != 0 {
        var empty_result string = ""
        var err error
        err.code = read_err.code
        err.message = "tcp read data: " + read_err.operation
        return empty_result, err
    }
    
    var ok_err error
    ok_err.code = 0
    return response_data.data, ok_err
}

func close_broker(broker* b) error {
    tcp_err := std.tcp.close(&b.connection)
    if tcp_err.code != 0 {
        var err error
        err.code = tcp_err.code
        err.message = "tcp close: " + tcp_err.operation
        return err
    }
    var ok_err error
    ok_err.code = 0
    return ok_err
}

func build_api_versions_request(string client_id, int correlation_id) string {
    return _put_int16(18) + _put_int16(0) + _put_int32(correlation_id) + _put_string(client_id)
}

func parse_api_versions_response(string response_data) (api_version[], error) {
    var c cursor
    c.data = response_data
    c.position = 0
    
    error_code, err1 := _read_int16(&c)
    if err1.code != 0 {
        var empty_versions api_version[]
        empty_versions = make([]api_version, 0)
        var result_err error
        result_err.code = err1.code
        result_err.message = "read error code"
        return empty_versions, result_err
    }
    
    if error_code != 0 {
        var empty_versions api_version[]
        empty_versions = make([]api_version, 0)
        var result_err error
        result_err.code = error_code
        result_err.message = "broker returned error"
        return empty_versions, result_err
    }
    
    count, err2 := _read_int32(&c)
    if err2.code != 0 {
        var empty_versions api_version[]
        empty_versions = make([]api_version, 0)
        var result_err error
        result_err.code = err2.code
        result_err.message = "read api version count"
        return empty_versions, result_err
    }
    
    if count < 0 || count > 256 {
        var empty_versions api_version[]
        empty_versions = make([]api_version, 0)
        var result_err error
        result_err.code = -1
        result_err.message = "invalid api version count"
        return empty_versions, result_err
    }
    
    versions := make([]api_version, count)
    i := 0
    while i < count {
        api_key, err3 := _read_int16(&c)
        if err3.code != 0 {
            var empty_versions api_version[]
            empty_versions = make([]api_version, 0)
            var result_err error
            result_err.code = err3.code
            result_err.message = "read api key"
            return empty_versions, result_err
        }
        
        min_ver, err4 := _read_int16(&c)
        if err4.code != 0 {
            var empty_versions api_version[]
            empty_versions = make([]api_version, 0)
            var result_err error
            result_err.code = err4.code
            result_err.message = "read min version"
            return empty_versions, result_err
        }
        
        max_ver, err5 := _read_int16(&c)
        if err5.code != 0 {
            var empty_versions api_version[]
            empty_versions = make([]api_version, 0)
            var result_err error
            result_err.code = err5.code
            result_err.message = "read max version"
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

func _put_int16(int value) string {
    high := (value >> 8) & 0xff
    low := value & 0xff
    return __std_byte_string(high) + __std_byte_string(low)
}

func _put_int32(int value) string {
    b3 := (value >> 24) & 0xff
    b2 := (value >> 16) & 0xff
    b1 := (value >> 8) & 0xff
    b0 := value & 0xff
    return __std_byte_string(b3) + __std_byte_string(b2) + __std_byte_string(b1) + __std_byte_string(b0)
}

func _put_string(string value) string {
    length := len(value)
    return _put_int16(length) + value
}

func _read_int16(cursor* c) (int, error) {
    if c.position + 2 > len(c.data) {
        var zero_val int = 0
        var err error
        err.code = 1
        err.message = "underrun"
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

func _read_int32(cursor* c) (int, error) {
    if c.position + 4 > len(c.data) {
        var zero_val int = 0
        var err error
        err.code = 1
        err.message = "underrun"
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

func _read_string(cursor* c) (string, error) {
    length, err := _read_int16(c)
    if err.code != 0 {
        var empty_str string = ""
        return empty_str, err
    }
    
    if length < 0 || length > 10000 {
        var empty_str string = ""
        var result_err error
        result_err.code = 1
        result_err.message = "invalid string length"
        return empty_str, result_err
    }
    
    if c.position + length > len(c.data) {
        var empty_str string = ""
        var result_err error
        result_err.code = 1
        result_err.message = "underrun"
        return empty_str, result_err
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
