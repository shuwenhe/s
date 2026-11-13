package std.kafka

const error_invalid = 1
const error_bounds = 2
const error_protocol = 3
const error_transport = 4
const error_timeout = 5
const error_broker = 6
const error_unsupported = 7
const error_closed = 8
const error_authentication = 9

struct error {
    int code
    int native_code
    string message
    bool fatal
}

func failure(int code, string message) error {
    return error { code: code, message: message }
}
