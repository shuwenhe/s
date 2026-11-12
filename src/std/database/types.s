package std.database
import ("std.option"; "std.result")

struct options {
    string host
    int port
    string database_name
    string user
    string password
    int connect_timeout_ms
    int read_timeout_ms
    int write_timeout_ms
    int max_packet_bytes
    string tls_server_name
    string tls_ca_file
    string server_public_key
    bool allow_public_key_retrieval
    int max_result_bytes
    int max_rows
}
const error_invalid = 1
const error_bounds = 2
const error_closed = 3
const error_busy = 4
const error_protocol = 5
const error_overflow = 6
const error_server = 7
const error_unsupported = 8
const error_authentication = 9
const error_transport = 10

// code == 0 is success. Native diagnostics never replace the portable category.
struct error {
    int code
    string message
    string sqlstate
    int native_code
    string driver
    bool fatal
}
struct native_value { string type_name, string data, bool binary_format }
// Binary values are binary-safe strings, not text and never NUL-terminated.
enum value {
    null,
    boolean(bool),
    integer(int),
    unsigned_integer(string),
    floating(string),
    decimal(string),
    text(string),
    binary(string),
    date(string),
    time(string),
    timestamp(string),
    timestamp_tz(string),
    json(string),
    uuid(string),
    native(native_value),
}
struct column { string name, string type_name, option[int] native_type, bool binary_format }
struct row { value[] values }
struct statement { string sql, value[] parameters }
// Decimal strings preserve the complete unsigned 64-bit MySQL metadata range.
struct result {
    option[string] affected_rows
    option[string] last_insert_id
    int warning_count
    string command_tag
}
func failure(int code, string message) error { return error { code: code, message: message } }
func is_null(value source) bool {
    return switch source { value::null : true, _ : false, }
}
func as_integer(value source) (int,error) {
    number := 0
    valid := false
    switch source {
        value::integer(item) : { number = item; valid = true },
        _ : {},
    }
    if !valid { return 0, failure(error_invalid,"value is not a signed integer") }
    return number, error { code: 0 }
}
// Accumulate negatively so the signed minimum is representable throughout.
func parse_integer(string text) (int,error) {
    if len(text) == 0 { return 0, failure(error_invalid,"empty integer") }
    index := 0
    negative := false
    first := _byte(text,0)
    if first == 45 || first == 43 { negative = first == 45; index = 1 }
    if index == len(text) { return 0, failure(error_invalid,"integer has no digits") }
    limit := -9223372036854775807
    if negative { limit = -9223372036854775808 }
    number := 0
    while index < len(text) {
        digit := _byte(text,index) - 48
        if digit < 0 || digit > 9 { return 0, failure(error_invalid,"invalid integer digit") }
        if number < limit / 10 { return 0, failure(error_overflow,"signed integer overflow") }
        number = number * 10
        if number < limit + digit { return 0, failure(error_overflow,"signed integer overflow") }
        number = number - digit
        index = index + 1
    }
    if negative { return number, error { code: 0 } }
    return 0 - number, error { code: 0 }
}
func unsigned_value(string text) (value,error) {
    if len(text) == 0 { return value.null, failure(error_invalid,"empty unsigned integer") }
    index := 0
    while index < len(text) {
        digit := _byte(text,index)
        if digit < 48 || digit > 57 { return value.null, failure(error_invalid,"invalid unsigned integer") }
        index = index + 1
    }
    start := 0
    while start < len(text) - 1 && _byte(text,start) == 48 { start = start + 1 }
    normalized := _slice(text,start,len(text))
    if len(normalized) > 20 { return value.null, failure(error_overflow,"unsigned integer overflow") }
    if len(normalized) == 20 && normalized > "18446744073709551615" { return value.null, failure(error_overflow,"unsigned integer overflow") }
    return value.unsigned_integer(normalized), error { code: 0 }
}
// Exact fixed-point decimal. Exponents and special numeric values need explicit
// driver conversion; they are never silently rounded through a floating value.
func decimal_value(string text) (value,error) {
    if len(text) == 0 { return value.null, failure(error_invalid,"empty decimal") }
    index := 0
    if _byte(text,0) == 45 || _byte(text,0) == 43 { index = 1 }
    digits := 0
    fractional := false
    fractional_digits := 0
    while index < len(text) {
        byte := _byte(text,index)
        if byte == 46 && !fractional && digits > 0 { fractional = true } else {
            if byte < 48 || byte > 57 { return value.null, failure(error_invalid,"invalid decimal") }
            digits = digits + 1
            if fractional { fractional_digits = fractional_digits + 1 }
        }
        index = index + 1
    }
    if digits == 0 || (fractional && fractional_digits == 0) { return value.null, failure(error_invalid,"decimal has no digits") }
    return value.decimal(text), error { code: 0 }
}
func (std.database.row self) get(int index) std.result.result[value,error] {
    if index < 0 || index >= len(self.values) { return std.result.result.err(failure(error_bounds,"column index out of bounds")) }
    return std.result.result.ok(self.values[index])
}
// These primitives are already implemented by both existing string runtimes.
extern "intrinsic" func __host_byte_at(string text, int index) int
extern "intrinsic" func __string_slice(string text, int start, int end) string
extern "intrinsic" func __std_byte_string(int byte) string
func _byte(string text, int index) int { return __host_byte_at(text,index) }
func _slice(string text, int start, int end) string { return __string_slice(text,start,end) }

// SQLSTATE is exactly five ASCII digits or uppercase letters on both protocols.
func valid_sqlstate(string text) bool {
    if len(text) != 5 { return false }
    index := 0
    while index < 5 {
        byte := _byte(text,index)
        if (byte < 48 || byte > 57) && (byte < 65 || byte > 90) { return false }
        index = index + 1
    }
    return true
}
