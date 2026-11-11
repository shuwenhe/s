package std.postgresql
import ("std.database"; "std.database.wire"; "std.option"; "std.prelude")

// PostgreSQL protocol 3.0 message codecs, independent of MySQL. No transport or
// authentication success is inferred from decoding an AuthenticationOk message.
struct message { int tag, string payload }
struct bound_parameter { option[string] data, int format }
struct column_definition {
    string name
    int table_oid
    int attribute_number
    int type_oid
    int type_size
    int type_modifier
    int format
}
struct authentication { int kind, string data }
struct parameter_status { string name, string value }
enum transaction_status { idle, active, failed }
func protocol_error(string text) std.database.error {
    return std.database.error { code: std.database.error_protocol, message: text, driver: "postgresql", fatal: true }
}
func _uint(int value, int width) string {
    bytes, error := std.database.wire.encode_uint(value,width,false)
    if error.code != 0 { panic("PostgreSQL internal wire integer invariant") }
    return bytes
}
func _has_zero(string text) bool {
    source := std.database.wire.cursor { data: text }
    while source.position < len(text) {
        if std.database.wire.read_byte(source*) == 0 { return true }
    }
    return false
}
func _valid_limit(int max_bytes) bool { return max_bytes >= 4 && max_bytes <= 16777216 }
func encode_message(int tag, string payload, int max_bytes) (string,std.database.error) {
    if !_valid_limit(max_bytes) || tag < 1 || tag > 255 { return "", std.database.failure(std.database.error_invalid,"invalid PostgreSQL message limit or tag") }
    if len(payload) > max_bytes - 4 { return "", protocol_error("PostgreSQL message exceeds configured limit") }
    return _uint(tag,1) + _uint(len(payload) + 4,4) + payload, std.database.error { code: 0 }
}
func decode_message(string data, int max_bytes) (message,std.database.error) {
    if !_valid_limit(max_bytes) { return message {}, std.database.failure(std.database.error_invalid,"invalid PostgreSQL message limit") }
    source := std.database.wire.cursor { data: data }
    tag := std.database.wire.read_byte(source*)
    length := std.database.wire.read_uint(source*,4,false)
    if source.code != 0 || tag == 0 || length < 4 || length > max_bytes || length != len(data) - 1 { return message {}, protocol_error("invalid PostgreSQL message length or tag") }
    payload := std.database.wire.read_bytes(source*,length - 4)
    return message { tag: tag, payload: payload }, std.database.error { code: 0 }
}
func ssl_request() string { return _uint(8,4) + _uint(80877103,4) }
func startup_message(string user, string database_name, int max_bytes) (string,std.database.error) {
    if !_valid_limit(max_bytes) || len(user) == 0 || _has_zero(user) || _has_zero(database_name) { return "", std.database.failure(std.database.error_invalid,"invalid PostgreSQL startup options") }
    if len(user) > max_bytes || len(database_name) > max_bytes - len(user) { return "", protocol_error("PostgreSQL startup exceeds configured limit") }
    zero := _uint(0,1)
    body := _uint(196608,4) + "user" + zero + user + zero + "database" + zero + database_name + zero + zero
    if len(body) > max_bytes - 4 { return "", protocol_error("PostgreSQL startup exceeds configured limit") }
    return _uint(len(body) + 4,4) + body, std.database.error { code: 0 }
}
func query_message(string sql, int max_bytes) (string,std.database.error) {
    if _has_zero(sql) { return "", std.database.failure(std.database.error_invalid,"NUL in PostgreSQL query") }
    return encode_message(81,sql + _uint(0,1),max_bytes)
}
// Balanced concatenation avoids quadratic prefix copying for large parameter lists.
func _oid_bytes(int[] oids, int start, int end) string {
    if start == end { return "" }
    if end - start == 1 { return _uint(oids[start],4) }
    middle := start + (end - start) / 2
    left := _oid_bytes(oids,start,middle)
    right := _oid_bytes(oids,middle,end)
    return left + right
}
func parse_message(string name, string sql, int[] type_oids, int max_bytes) (string,std.database.error) {
    if !_valid_limit(max_bytes) || _has_zero(name) || _has_zero(sql) || len(type_oids) > 65535 { return "", std.database.failure(std.database.error_invalid,"invalid PostgreSQL Parse fields") }
    if len(name) > max_bytes || len(sql) > max_bytes - len(name) { return "", protocol_error("PostgreSQL Parse exceeds configured limit") }
    fixed := len(name) + len(sql) + 8
    if fixed > max_bytes || len(type_oids) > (max_bytes - fixed) / 4 { return "", protocol_error("PostgreSQL Parse exceeds configured limit") }
    index := 0
    while index < len(type_oids) {
        oid := type_oids[index]
        if oid < 0 || oid > 4294967295 { return "", std.database.failure(std.database.error_invalid,"invalid PostgreSQL type OID") }
        index = index + 1
    }
    body := name + _uint(0,1) + sql + _uint(0,1) + _uint(len(type_oids),2)
    return encode_message(80,body + _oid_bytes(type_oids,0,len(type_oids)),max_bytes)
}
func _format_bytes(bound_parameter[] parameters, int start, int end) string {
    if start == end { return "" }
    if end - start == 1 { return _uint(parameters[start].format,2) }
    middle := start + (end - start) / 2
    left := _format_bytes(parameters,start,middle)
    right := _format_bytes(parameters,middle,end)
    return left + right
}
func _parameter_bytes(bound_parameter[] parameters, int start, int end) string {
    if start == end { return "" }
    if end - start == 1 {
        parameter := parameters[start]
        if parameter.data.is_none() { return _uint(4294967295,4) }
        bytes := parameter.data.unwrap()
        return _uint(len(bytes),4) + bytes
    }
    middle := start + (end - start) / 2
    left := _parameter_bytes(parameters,start,middle)
    right := _parameter_bytes(parameters,middle,end)
    return left + right
}
// Bind carries values separately from SQL. Binary parameters require the Parse
// OID and the supplied bytes to agree; no unsafe SQL interpolation is performed.
func bind_message(string portal, string name, bound_parameter[] parameters, int max_bytes) (string,std.database.error) {
    if !_valid_limit(max_bytes) || _has_zero(portal) || _has_zero(name) || len(parameters) > 65535 { return "", std.database.failure(std.database.error_invalid,"invalid PostgreSQL Bind fields") }
    if len(portal) > max_bytes || len(name) > max_bytes - len(portal) { return "", protocol_error("PostgreSQL Bind exceeds configured limit") }
    // Includes the length header, both terminators, three counts and all
    // parameter formats and lengths. All arithmetic stays below small bounds.
    total := len(portal) + len(name) + 12
    if total > max_bytes || len(parameters) > (max_bytes - total) / 6 { return "", protocol_error("PostgreSQL Bind exceeds configured limit") }
    total = total + len(parameters) * 6
    index := 0
    while index < len(parameters) {
        parameter := parameters[index]
        if parameter.format != 0 && parameter.format != 1 { return "", std.database.failure(std.database.error_invalid,"invalid PostgreSQL parameter format") }
        if parameter.data.is_some() {
            bytes := parameter.data.unwrap()
            if len(bytes) > max_bytes - total { return "", protocol_error("PostgreSQL parameter exceeds configured limit") }
            total = total + len(bytes)
        }
        index = index + 1
    }
    body := portal + _uint(0,1) + name + _uint(0,1) + _uint(len(parameters),2)
    body = body + _format_bytes(parameters,0,len(parameters)) + _uint(len(parameters),2)
    body = body + _parameter_bytes(parameters,0,len(parameters)) + _uint(0,2)
    // Zero result-format codes requests text results for every column.
    return encode_message(66,body,max_bytes)
}
func describe_statement_message(string name, int max_bytes) (string,std.database.error) {
    if _has_zero(name) { return "", std.database.failure(std.database.error_invalid,"NUL in PostgreSQL statement name") }
    return encode_message(68,"S" + name + _uint(0,1),max_bytes)
}
func execute_message(string portal, int max_rows, int max_bytes) (string,std.database.error) {
    if _has_zero(portal) || max_rows < 0 || max_rows > 2147483647 { return "", std.database.failure(std.database.error_invalid,"invalid PostgreSQL Execute fields") }
    return encode_message(69,portal + _uint(0,1) + _uint(max_rows,4),max_bytes)
}
func close_statement_message(string name, int max_bytes) (string,std.database.error) {
    if _has_zero(name) { return "", std.database.failure(std.database.error_invalid,"NUL in PostgreSQL statement name") }
    return encode_message(67,"S" + name + _uint(0,1),max_bytes)
}
func sync_message() string { return "S" + _uint(4,4) }
func terminate_message() string { return "X" + _uint(4,4) }
func decode_row_description(string payload) (column_definition[],std.database.error) {
    source := std.database.wire.cursor { data: payload }
    count := std.database.wire.read_uint(source*,2,false)
    if source.code != 0 || count > (len(payload) - 2) / 19 { return column_definition[](), protocol_error("invalid PostgreSQL column count") }
    columns := column_definition[]()
    index := 0
    while index < count {
        name := std.database.wire.read_cstring(source*)
        table_oid := std.database.wire.read_uint(source*,4,false)
        attribute := std.database.wire.read_uint(source*,2,false)
        type_oid := std.database.wire.read_uint(source*,4,false)
        type_size := std.database.wire.read_uint(source*,2,false)
        modifier := std.database.wire.read_uint(source*,4,false)
        format := std.database.wire.read_uint(source*,2,false)
        if source.code != 0 || (format != 0 && format != 1) { return column_definition[](), protocol_error("invalid PostgreSQL column metadata") }
        if attribute > 32767 { attribute = attribute - 65536 }
        if type_size > 32767 { type_size = type_size - 65536 }
        if modifier > 2147483647 { modifier = modifier - 4294967296 }
        column := column_definition { name: name, table_oid: table_oid, attribute_number: attribute, type_oid: type_oid, type_size: type_size, type_modifier: modifier, format: format }
        columns = append(columns,column)
        index = index + 1
    }
    if source.position != len(payload) { return column_definition[](), protocol_error("extra PostgreSQL column bytes") }
    return columns, std.database.error { code: 0 }
}
func decode_data_row(string payload, column_definition[] columns) (std.database.row,std.database.error) {
    source := std.database.wire.cursor { data: payload }
    count := std.database.wire.read_uint(source*,2,false)
    if source.code != 0 || count != len(columns) || count > (len(payload) - 2) / 4 { return std.database.row {}, protocol_error("invalid PostgreSQL DataRow count") }
    values := std.database.value[]()
    index := 0
    while index < count {
        size := std.database.wire.read_uint(source*,4,false)
        item := std.database.value.null
        if size != 4294967295 {
            if size > 2147483647 { return std.database.row {}, protocol_error("negative PostgreSQL DataRow size") }
            text := std.database.wire.read_bytes(source*,size)
            format := columns[index].format
            if format == 0 { item = std.database.value.text(text) } else {
                if format != 1 { return std.database.row {}, protocol_error("invalid PostgreSQL DataRow format") }
                item = std.database.value.binary(text)
            }
        }
        if source.code != 0 { return std.database.row {}, protocol_error("truncated PostgreSQL DataRow") }
        values = append(values,item)
        index = index + 1
    }
    if source.position != len(payload) { return std.database.row {}, protocol_error("extra PostgreSQL DataRow bytes") }
    return std.database.row { values: values }, std.database.error { code: 0 }
}
func decode_error(string payload) std.database.error {
    source := std.database.wire.cursor { data: payload }
    sqlstate := ""
    message := ""
    severity := ""
    nonlocalized_severity := ""
    while source.position < len(payload) {
        tag := std.database.wire.read_byte(source*)
        if tag == 0 {
            if source.position != len(payload) || !std.database.valid_sqlstate(sqlstate) || len(message) == 0 || len(severity) == 0 { return protocol_error("invalid PostgreSQL ErrorResponse fields") }
            actual_severity := severity
            if len(nonlocalized_severity) != 0 { actual_severity = nonlocalized_severity }
            return std.database.error { code: std.database.error_server, message: message, sqlstate: sqlstate, driver: "postgresql", fatal: actual_severity == "FATAL" || actual_severity == "PANIC" }
        }
        value := std.database.wire.read_cstring(source*)
        if source.code != 0 { return protocol_error("truncated PostgreSQL ErrorResponse") }
        if tag == 67 { if len(sqlstate) != 0 { return protocol_error("duplicate PostgreSQL SQLSTATE") }
            sqlstate = value }
        if tag == 77 { if len(message) != 0 { return protocol_error("duplicate PostgreSQL error message") }
            message = value }
        if tag == 83 {
            if len(severity) != 0 { return protocol_error("duplicate PostgreSQL localized severity") }
            severity = value
        }
        if tag == 86 {
            if len(nonlocalized_severity) != 0 { return protocol_error("duplicate PostgreSQL nonlocalized severity") }
            nonlocalized_severity = value
        }
    }
    return protocol_error("unterminated PostgreSQL ErrorResponse")
}
func decode_ready(string payload) (transaction_status,std.database.error) {
    if payload == "I" { return transaction_status.idle, std.database.error { code: 0 } }
    if payload == "T" { return transaction_status.active, std.database.error { code: 0 } }
    if payload == "E" { return transaction_status.failed, std.database.error { code: 0 } }
    return transaction_status.idle, protocol_error("invalid PostgreSQL ReadyForQuery status")
}
func decode_authentication(string payload) (authentication,std.database.error) {
    source := std.database.wire.cursor { data: payload }
    kind := std.database.wire.read_uint(source*,4,false)
    if source.code != 0 { return authentication {}, protocol_error("truncated PostgreSQL authentication request") }
    remaining := len(payload) - source.position
    data := std.database.wire.read_bytes(source*,remaining)
    if kind == 0 || kind == 3 {
        if len(data) != 0 { return authentication {}, protocol_error("unexpected PostgreSQL authentication data") }
    } else {
        if kind == 5 {
            if len(data) != 4 { return authentication {}, protocol_error("invalid PostgreSQL MD5 salt") }
        } else {
            if kind == 10 {
                mechanisms := std.database.wire.cursor { data: data }
                count := 0
                terminated := false
                while mechanisms.position < len(data) {
                    mechanism := std.database.wire.read_cstring(mechanisms*)
                    if mechanisms.code != 0 { return authentication {}, protocol_error("invalid PostgreSQL SASL mechanism list") }
                    if len(mechanism) == 0 { terminated = true; break }
                    count = count + 1
                }
                if !terminated || count == 0 || mechanisms.position != len(data) { return authentication {}, protocol_error("invalid PostgreSQL SASL list terminator") }
            } else {
                if kind != 11 && kind != 12 { return authentication {}, std.database.failure(std.database.error_unsupported,"PostgreSQL authentication mechanism is unsupported") }
                if len(data) == 0 { return authentication {}, protocol_error("empty PostgreSQL SASL message") }
            }
        }
    }
    return authentication { kind: kind, data: data }, std.database.error { code: 0 }
}
func decode_parameter_status(string payload) (parameter_status,std.database.error) {
    source := std.database.wire.cursor { data: payload }
    name := std.database.wire.read_cstring(source*)
    value := std.database.wire.read_cstring(source*)
    if source.code != 0 || len(name) == 0 || source.position != len(payload) { return parameter_status {}, protocol_error("invalid PostgreSQL ParameterStatus") }
    return parameter_status { name: name, value: value }, std.database.error { code: 0 }
}
func decode_command_complete(string payload) (std.database.result,std.database.error) {
    source := std.database.wire.cursor { data: payload }
    tag := std.database.wire.read_cstring(source*)
    if source.code != 0 || source.position != len(payload) || len(tag) == 0 { return std.database.result {}, protocol_error("invalid PostgreSQL CommandComplete") }
    scan := std.database.wire.cursor { data: tag }
    first_space := -1
    last_space := -1
    while scan.position < len(tag) {
        position := scan.position
        if std.database.wire.read_byte(scan*) == 32 {
            if first_space < 0 { first_space = position }
            last_space = position
        }
    }
    affected := option[string].none
    if first_space >= 0 {
        command := std.prelude.prelude_slice(tag,0,first_space)
        if command == "INSERT" || command == "UPDATE" || command == "DELETE" || command == "SELECT" || command == "MERGE" || command == "MOVE" || command == "FETCH" || command == "COPY" {
            count := std.prelude.prelude_slice(tag,last_space + 1,len(tag))
            checked, validation := std.database.unsigned_value(count)
            if validation.code != 0 { return std.database.result {}, protocol_error("invalid PostgreSQL command row count") }
            affected = option.some(count)
        }
    }
    return std.database.result { affected_rows: affected, last_insert_id: option[string].none, command_tag: tag }, std.database.error { code: 0 }
}
