package std.mysql
import ("std.database"; "std.database.wire"; "std.option"; "std.prelude")

// Single physical packet codecs. A 0xffffff length denotes fragmentation and is
// explicitly unsupported until a bounded logical-message assembler is available.
struct packet { int sequence, string payload }
struct length_encoded { bool is_null, string number }
struct handshake {
    string server_version
    int connection_id
    int capabilities
    int charset
    int status
    string scramble
    string auth_plugin
}
struct ok_packet { std.database.result metadata, int status, string info }
func protocol_error(string message) std.database.error {
    return std.database.error { code: std.database.error_protocol, message: message, driver: "mysql", fatal: true }
}
func encode_packet(string payload, int sequence, int max_bytes) (string,std.database.error) {
    if sequence < 0 || sequence > 255 || max_bytes < 1 || max_bytes > 16777214 {
        return "", std.database.failure(std.database.error_invalid,"invalid MySQL packet limits or sequence")
    }
    if len(payload) > max_bytes { return "", protocol_error("MySQL packet exceeds configured limit") }
    header, error := std.database.wire.encode_uint(len(payload),3,true)
    serial, serial_error := std.database.wire.encode_uint(sequence,1,true)
    if error.code != 0 { return "", error }
    if serial_error.code != 0 { return "", serial_error }
    return header + serial + payload, std.database.error { code: 0 }
}
func decode_packet(string data, int expected_sequence, int max_bytes) (packet,std.database.error) {
    if expected_sequence < 0 || expected_sequence > 255 || max_bytes < 1 || max_bytes > 16777214 {
        return packet {}, std.database.failure(std.database.error_invalid,"invalid MySQL packet limits or sequence")
    }
    source := std.database.wire.cursor { data: data }
    length := std.database.wire.read_uint(source*,3,true)
    sequence := std.database.wire.read_byte(source*)
    if source.code != 0 { return packet {}, protocol_error("truncated MySQL packet header") }
    if length == 16777215 { return packet {}, std.database.failure(std.database.error_unsupported,"fragmented MySQL messages are not implemented") }
    if length > max_bytes || length != len(data) - 4 || sequence != expected_sequence {
        return packet {}, protocol_error("invalid MySQL packet length or sequence")
    }
    payload := std.database.wire.read_bytes(source*,length)
    return packet { sequence: sequence, payload: payload }, std.database.error { code: 0 }
}
func read_lenenc(std.database.wire.cursor* source) length_encoded {
    first := std.database.wire.read_byte(source*)
    if source.code != 0 { return length_encoded {} }
    if first <= 250 { return length_encoded { number: std.prelude.to_string(first) } }
    if first == 251 { return length_encoded { is_null: true } }
    width := 0
    if first == 252 { width = 2 }
    if first == 253 { width = 3 }
    if first == 254 { width = 8 }
    if width == 0 { source.code = std.database.error_protocol; return length_encoded {} }
    number := std.database.wire.read_uint_decimal(source*,width,true)
    return length_encoded { number: number }
}
func read_field(std.database.wire.cursor* source) option[string] {
    size := read_lenenc(source*)
    if source.code != 0 || size.is_null { return option[string].none }
    length, error := std.database.parse_integer(size.number)
    if error.code != 0 { source.code = std.database.error_protocol; return option[string].none }
    text := std.database.wire.read_bytes(source*,length)
    if source.code != 0 { return option[string].none }
    return option.some(text)
}
func decode_handshake(string payload) (handshake,std.database.error) {
    source := std.database.wire.cursor { data: payload }
    version := std.database.wire.read_byte(source*)
    if source.code != 0 { return handshake {}, protocol_error("empty MySQL handshake") }
    if version != 10 { return handshake {}, std.database.failure(std.database.error_unsupported,"MySQL protocol version is not 10") }
    server_version := std.database.wire.read_cstring(source*)
    connection_id := std.database.wire.read_uint(source*,4,true)
    scramble := std.database.wire.read_bytes(source*,8)
    filler := std.database.wire.read_byte(source*)
    low := std.database.wire.read_uint(source*,2,true)
    charset := std.database.wire.read_byte(source*)
    status := std.database.wire.read_uint(source*,2,true)
    high := std.database.wire.read_uint(source*,2,true)
    auth_length := std.database.wire.read_byte(source*)
    reserved := std.database.wire.read_bytes(source*,10)
    if source.code != 0 || filler != 0 || len(server_version) == 0 { return handshake {}, protocol_error("truncated or malformed MySQL handshake") }
    padding := std.database.wire.cursor { data: reserved }
    index := 0
    while index < 10 {
        if std.database.wire.read_byte(padding*) != 0 { return handshake {}, protocol_error("nonzero handshake reserved byte") }
        index = index + 1
    }
    capabilities := low + high * 65536
    if (capabilities & 512) == 0 || (capabilities & 32768) == 0 {
        return handshake {}, std.database.failure(std.database.error_unsupported,"MySQL protocol 4.1 and secure connection required")
    }
    plugin_auth := (capabilities & 524288) != 0
    second_length := 13
    if plugin_auth {
        if auth_length != 21 { return handshake {}, std.database.failure(std.database.error_unsupported,"unsupported MySQL authentication scramble length") }
        second_length = auth_length - 8
    }
    second := std.database.wire.read_bytes(source*,second_length)
    if source.code != 0 { return handshake {}, protocol_error("truncated MySQL authentication scramble") }
    second_source := std.database.wire.cursor { data: second, position: second_length - 1 }
    if std.database.wire.read_byte(second_source*) != 0 { return handshake {}, protocol_error("unterminated MySQL authentication scramble") }
    scramble = scramble + std.prelude.prelude_slice(second,0,second_length - 1)
    plugin := "mysql_native_password"
    if plugin_auth { plugin = std.database.wire.read_cstring(source*) }
    if source.code != 0 || source.position != len(payload) || len(plugin) == 0 {
        return handshake {}, protocol_error("invalid MySQL authentication plugin name")
    }
    return handshake { server_version: server_version, connection_id: connection_id, capabilities: capabilities, charset: charset, status: status, scramble: scramble, auth_plugin: plugin }, std.database.error { code: 0 }
}
func decode_ok(string payload) (ok_packet,std.database.error) {
    source := std.database.wire.cursor { data: payload }
    header := std.database.wire.read_byte(source*)
    if source.code != 0 || (header != 0 && header != 254) { return ok_packet {}, protocol_error("invalid MySQL OK header") }
    affected := read_lenenc(source*)
    inserted := read_lenenc(source*)
    status := std.database.wire.read_uint(source*,2,true)
    warnings := std.database.wire.read_uint(source*,2,true)
    if source.code != 0 || affected.is_null || inserted.is_null { return ok_packet {}, protocol_error("invalid MySQL OK fields") }
    remaining := len(payload) - source.position
    info := std.database.wire.read_bytes(source*,remaining)
    metadata := std.database.result { affected_rows: option.some(affected.number), last_insert_id: option.some(inserted.number), warning_count: warnings }
    return ok_packet { metadata: metadata, status: status, info: info }, std.database.error { code: 0 }
}
func decode_error(string payload) std.database.error {
    source := std.database.wire.cursor { data: payload }
    header := std.database.wire.read_byte(source*)
    code := std.database.wire.read_uint(source*,2,true)
    marker := std.database.wire.read_byte(source*)
    sqlstate := std.database.wire.read_bytes(source*,5)
    if source.code != 0 || header != 255 || marker != 35 || code == 0 || !std.database.valid_sqlstate(sqlstate) { return protocol_error("invalid MySQL ERR packet") }
    remaining := len(payload) - source.position
    message := std.database.wire.read_bytes(source*,remaining)
    return std.database.error { code: std.database.error_server, message: message, sqlstate: sqlstate, native_code: code, driver: "mysql" }
}
// Text protocol cells stay text until column metadata determines a safe typed
// conversion. In particular this function does not guess text versus BLOB.
func decode_text_row(string payload, int column_count) (std.database.row,std.database.error) {
    if column_count < 0 || column_count > len(payload) { return std.database.row {}, protocol_error("invalid MySQL row column count") }
    source := std.database.wire.cursor { data: payload }
    values := std.database.value[]()
    index := 0
    while index < column_count {
        field := read_field(source*)
        if source.code != 0 { return std.database.row {}, protocol_error("invalid MySQL text field") }
        item := std.database.value.null
        if field.is_some() { item = std.database.value.text(field.unwrap()) }
        values = append(values,item)
        index = index + 1
    }
    if source.position != len(payload) { return std.database.row {}, protocol_error("extra MySQL row bytes") }
    return std.database.row { values: values }, std.database.error { code: 0 }
}
func _sql_command(int command, string sql, int max_bytes) (string,std.database.error) {
    if max_bytes < 1 || max_bytes > 16777214 { return "", std.database.failure(std.database.error_invalid,"invalid MySQL command size limit") }
    if len(sql) > max_bytes - 1 { return "", protocol_error("MySQL command exceeds configured limit") }
    prefix, error := std.database.wire.encode_uint(command,1,true)
    if error.code != 0 { return "", error }
    return prefix + sql, std.database.error { code: 0 }
}
func query_command(string sql, int max_bytes) (string,std.database.error) { return _sql_command(3,sql,max_bytes) }
func prepare_command(string sql, int max_bytes) (string,std.database.error) { return _sql_command(22,sql,max_bytes) }
func close_statement_command(int statement_id) (string,std.database.error) {
    id, error := std.database.wire.encode_uint(statement_id,4,true)
    if error.code != 0 { return "", error }
    prefix, prefix_error := std.database.wire.encode_uint(25,1,true)
    if prefix_error.code != 0 { return "", prefix_error }
    return prefix + id, std.database.error { code: 0 }
}

struct prepared_info { int statement_id, int column_count, int parameter_count, int warning_count }
struct column_definition {
    string schema
    string table
    string original_table
    string name
    string original_name
    int charset
    int max_length
    int type_id
    int flags
    int decimals
}
struct auth_switch { string plugin, string scramble }
func decode_prepare_ok(string payload) (prepared_info,std.database.error) {
    source := std.database.wire.cursor { data: payload }
    header := std.database.wire.read_byte(source*)
    id := std.database.wire.read_uint(source*,4,true)
    columns := std.database.wire.read_uint(source*,2,true)
    parameters := std.database.wire.read_uint(source*,2,true)
    filler := std.database.wire.read_byte(source*)
    warnings := std.database.wire.read_uint(source*,2,true)
    if source.code != 0 || header != 0 || filler != 0 || source.position != len(payload) {
        return prepared_info {}, protocol_error("invalid MySQL prepare response")
    }
    return prepared_info { statement_id: id, column_count: columns, parameter_count: parameters, warning_count: warnings }, std.database.error { code: 0 }
}
func decode_column(string payload) (column_definition,std.database.error) {
    source := std.database.wire.cursor { data: payload }
    catalog := read_field(source*)
    schema := read_field(source*)
    table := read_field(source*)
    original_table := read_field(source*)
    name := read_field(source*)
    original_name := read_field(source*)
    fixed := read_lenenc(source*)
    charset := std.database.wire.read_uint(source*,2,true)
    max_length := std.database.wire.read_uint(source*,4,true)
    type_id := std.database.wire.read_byte(source*)
    flags := std.database.wire.read_uint(source*,2,true)
    decimals := std.database.wire.read_byte(source*)
    filler := std.database.wire.read_uint(source*,2,true)
    if source.code != 0 || catalog.is_none() || schema.is_none() || table.is_none() || original_table.is_none() || name.is_none() || original_name.is_none() || fixed.is_null || fixed.number != "12" || filler != 0 || source.position != len(payload) {
        return column_definition {}, protocol_error("invalid MySQL column definition")
    }
    if catalog.unwrap() != "def" { return column_definition {}, protocol_error("invalid MySQL column catalog") }
    return column_definition { schema: schema.unwrap(), table: table.unwrap(), original_table: original_table.unwrap(), name: name.unwrap(), original_name: original_name.unwrap(), charset: charset, max_length: max_length, type_id: type_id, flags: flags, decimals: decimals }, std.database.error { code: 0 }
}
func decode_auth_switch(string payload) (auth_switch,std.database.error) {
    source := std.database.wire.cursor { data: payload }
    header := std.database.wire.read_byte(source*)
    plugin := std.database.wire.read_cstring(source*)
    remaining := len(payload) - source.position
    scramble := std.database.wire.read_bytes(source*,remaining)
    if source.code != 0 || header != 254 || len(plugin) == 0 || len(scramble) == 0 { return auth_switch {}, protocol_error("invalid MySQL authentication switch") }
    tail := std.database.wire.cursor { data: scramble, position: len(scramble) - 1 }
    if std.database.wire.read_byte(tail*) == 0 { scramble = std.prelude.prelude_slice(scramble,0,len(scramble) - 1) }
    if len(scramble) != 20 { return auth_switch {}, std.database.failure(std.database.error_unsupported,"unsupported MySQL authentication switch scramble length") }
    return auth_switch { plugin: plugin, scramble: scramble }, std.database.error { code: 0 }
}
func encode_length_string(string text) (string,std.database.error) {
    length := len(text)
    if length > 16777214 { return "", protocol_error("MySQL parameter exceeds physical packet limit") }
    marker := ""
    width := 1
    if length > 250 {
        width = 2
        encoded, marker_error := std.database.wire.encode_uint(252,1,true)
        if marker_error.code != 0 { return "", marker_error }
        marker = encoded
    }
    if length > 65535 {
        width = 3
        encoded, marker_error := std.database.wire.encode_uint(253,1,true)
        if marker_error.code != 0 { return "", marker_error }
        marker = encoded
    }
    prefix, error := std.database.wire.encode_uint(length,width,true)
    if error.code != 0 { return "", error }
    return marker + prefix + text, std.database.error { code: 0 }
}
func _signed_integer_bytes(int number) string {
    bytes := ""
    remaining := number
    index := 0
    while index < 8 {
        byte := remaining % 256
        if byte < 0 { byte = byte + 256 }
        encoded, error := std.database.wire.encode_uint(byte,1,true)
        if error.code != 0 { panic("MySQL integer byte invariant") }
        bytes = bytes + encoded
        remaining = (remaining - byte) / 256
        index = index + 1
    }
    return bytes
}
func _decimal_divide(string text) (string,int) {
    quotient := ""
    remainder := 0
    source := std.database.wire.cursor { data: text }
    while source.position < len(text) {
        digit := std.database.wire.read_byte(source*) - 48
        number := remainder * 10 + digit
        next := number / 256
        remainder = number % 256
        if next != 0 || len(quotient) > 0 {
            encoded, error := std.database.wire.encode_uint(48 + next,1,true)
            if error.code != 0 { panic("MySQL decimal digit invariant") }
            quotient = quotient + encoded
        }
    }
    if len(quotient) == 0 { quotient = "0" }
    return quotient,remainder
}
func _unsigned_integer_bytes(string number) (string,std.database.error) {
    checked, error := std.database.unsigned_value(number)
    if error.code != 0 { return "", error }
    text := number
    bytes := ""
    index := 0
    while index < 8 {
        quotient, remainder := _decimal_divide(text)
        text = quotient
        encoded, byte_error := std.database.wire.encode_uint(remainder,1,true)
        if byte_error.code != 0 { return "", byte_error }
        bytes = bytes + encoded
        index = index + 1
    }
    return bytes, std.database.error { code: 0 }
}
struct _bound_parameter { int type_id, bool unsigned, bool is_null, string data }
func _bind_parameter(std.database.value source) (_bound_parameter,std.database.error) {
    parameter := _bound_parameter {}
    problem := std.database.error { code: 0 }
    switch source {
        std.database.value::null : { parameter.type_id = 6; parameter.is_null = true },
        std.database.value::boolean(value) : {
            parameter.type_id = 1
            number := 0
            if value { number = 1 }
            encoded, error := std.database.wire.encode_uint(number,1,true)
            parameter.data = encoded
            problem = error
        },
        std.database.value::integer(value) : { parameter.type_id = 8; parameter.data = _signed_integer_bytes(value) },
        std.database.value::unsigned_integer(value) : {
            parameter.type_id = 8
            parameter.unsigned = true
            encoded, error := _unsigned_integer_bytes(value)
            parameter.data = encoded
            problem = error
        },
        std.database.value::text(value) : {
            parameter.type_id = 253
            encoded, error := encode_length_string(value)
            parameter.data = encoded
            problem = error
        },
        std.database.value::binary(value) : {
            parameter.type_id = 252
            encoded, error := encode_length_string(value)
            parameter.data = encoded
            problem = error
        },
        std.database.value::decimal(value) : {
            parameter.type_id = 246
            checked, validation := std.database.decimal_value(value)
            if validation.code != 0 { problem = validation } else {
                encoded, error := encode_length_string(value)
                parameter.data = encoded
                problem = error
            }
        },
        _ : { problem = std.database.failure(std.database.error_unsupported,"MySQL binary parameter type is not implemented") },
    }
    return parameter,problem
}
func execute_statement_command(int statement_id, std.database.value[] parameters, int max_bytes) (string,std.database.error) {
    if max_bytes < 10 || max_bytes > 16777214 || len(parameters) > 65535 { return "", std.database.failure(std.database.error_invalid,"invalid MySQL execute limits") }
    id, error := std.database.wire.encode_uint(statement_id,4,true)
    if error.code != 0 { return "", error }
    command, command_error := std.database.wire.encode_uint(23,1,true)
    zero, zero_error := std.database.wire.encode_uint(0,1,true)
    iteration, iteration_error := std.database.wire.encode_uint(1,4,true)
    if command_error.code != 0 { return "", command_error }
    if zero_error.code != 0 { return "", zero_error }
    if iteration_error.code != 0 { return "", iteration_error }
    header := command + id + zero + iteration
    if len(parameters) == 0 { return header, std.database.error { code: 0 } }
    bitmap := ""
    bitmap_byte := 0
    mask := 1
    types := ""
    values := ""
    index := 0
    while index < len(parameters) {
        parameter, parameter_error := _bind_parameter(parameters[index])
        if parameter_error.code != 0 { return "", parameter_error }
        if parameter.is_null { bitmap_byte = bitmap_byte + mask }
        mask = mask * 2
        if mask == 256 || index == len(parameters) - 1 {
            encoded, bitmap_error := std.database.wire.encode_uint(bitmap_byte,1,true)
            if bitmap_error.code != 0 { return "", bitmap_error }
            bitmap = bitmap + encoded
            bitmap_byte = 0
            mask = 1
        }
        flags := 0
        if parameter.unsigned { flags = 128 }
        type_byte, type_error := std.database.wire.encode_uint(parameter.type_id,1,true)
        flag_byte, flag_error := std.database.wire.encode_uint(flags,1,true)
        if type_error.code != 0 { return "", type_error }
        if flag_error.code != 0 { return "", flag_error }
        if len(parameter.data) > max_bytes - len(values) { return "", protocol_error("MySQL parameter bytes exceed configured limit") }
        types = types + type_byte + flag_byte
        values = values + parameter.data
        index = index + 1
    }
    // Every partial component is bounded independently before concatenation.
    if len(bitmap) + len(types) + 11 > max_bytes { return "", protocol_error("MySQL parameter metadata exceeds configured limit") }
    available := max_bytes - len(bitmap) - len(types) - 11
    if len(values) > available { return "", protocol_error("MySQL execute exceeds configured limit") }
    one, one_error := std.database.wire.encode_uint(1,1,true)
    if one_error.code != 0 { return "", one_error }
    return header + bitmap + one + types + values, std.database.error { code: 0 }
}
