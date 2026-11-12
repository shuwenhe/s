package std.mysql
import ("std.database"; "std.database.wire"; "std.option"; "std.prelude")

struct response { std.database.rows rows, std.database.result metadata, bool has_rows }
func _status(connection* client, int status) std.database.error {
    if (status & 8) != 0 {
        problem := std.database.failure(std.database.error_unsupported,"multiple MySQL result sets are not supported")
        return _fatal(client*,problem)
    }
    client.in_transaction = (status & 1) != 0
    return std.database.error {}
}
func _eof(connection* client, string payload) std.database.error {
    source := std.database.wire.cursor { data: payload }
    header := std.database.wire.read_byte(source*)
    warnings := std.database.wire.read_uint(source*,2,true)
    status := std.database.wire.read_uint(source*,2,true)
    if source.code != 0 || header != 254 || len(payload) != 5 {
        problem := protocol_error("invalid MySQL EOF packet")
        return _fatal(client*,problem)
    }
    return _status(client*,status)
}
func _typed_text_row(string payload, column_definition[] definitions) (std.database.row,std.database.error) {
    source := std.database.wire.cursor { data: payload }
    values := std.database.value[]()
    index := 0
    while index < len(definitions) {
        field := read_field(source*)
        if source.code != 0 { return std.database.row {},protocol_error("invalid MySQL text row") }
        value := std.database.value.null
        if field.is_some() {
            text := field.unwrap()
            converted,error := _text_value(text,definitions[index])
            if error.code != 0 { return std.database.row {},error }
            value = converted
        }
        values = append(values,value)
        index = index + 1
    }
    if source.position != len(payload) { return std.database.row {},protocol_error("extra MySQL text row bytes") }
    return std.database.row { values: values },std.database.error {}
}
func _read_response(connection* client, bool binary) (response,std.database.error) {
    first,error := _read_packet(client*)
    if error.code != 0 { return response {},error }
    if len(first) == 0 { problem := protocol_error("empty MySQL response"); return response {},_fatal(client*,problem) }
    header := std.database._byte(first,0)
    if header == 255 { return response {},_server_error(client*,first) }
    if header == 0 {
        ok,problem := decode_ok(first)
        if problem.code != 0 { return response {},_fatal(client*,problem) }
        status_error := _status(client*,ok.status)
        return response { metadata: ok.metadata },status_error
    }
    if header == 251 { problem := std.database.failure(std.database.error_unsupported,"LOCAL INFILE is disabled"); return response {},_fatal(client*,problem) }
    cursor := std.database.wire.cursor { data: first }
    count_field := read_lenenc(cursor*)
    count,count_error := std.database.parse_integer(count_field.number)
    if cursor.code != 0 || cursor.position != len(first) || count_field.is_null || count_error.code != 0 || count < 1 || count > 4096 {
        problem := protocol_error("invalid MySQL column count")
        return response {},_fatal(client*,problem)
    }
    definitions := column_definition[]()
    columns := std.database.column[]()
    used := len(first)
    index := 0
    while index < count {
        packet,error := _read_packet(client*)
        if error.code != 0 { return response {},error }
        used = used + len(packet)
        if used > client.config.max_result_bytes { return response {},_transport_error(client*,0,"MySQL result exceeds max_result_bytes") }
        if len(packet) > 0 && std.database._byte(packet,0) == 255 { return response {},_server_error(client*,packet) }
        definition,problem := decode_column(packet)
        if problem.code != 0 { return response {},_fatal(client*,problem) }
        definitions = append(definitions,definition)
        type_name := _type_name(definition.type_id)
        columns = append(columns,std.database.column { name: definition.name, type_name: type_name, native_type: option.some(definition.type_id), binary_format: binary })
        index = index + 1
    }
    separator,separator_error := _read_packet(client*)
    if separator_error.code != 0 { return response {},separator_error }
    eof_error := _eof(client*,separator)
    if eof_error.code != 0 { return response {},eof_error }
    rows := std.database.row[]()
    while true {
        payload,read_error := _read_packet(client*)
        if read_error.code != 0 { return response {},read_error }
        if len(payload) == 0 { return response {},_transport_error(client*,0,"empty MySQL row") }
        header := std.database._byte(payload,0)
        if header == 255 { return response {},_server_error(client*,payload) }
        if header == 254 && len(payload) < 9 {
            final_error := _eof(client*,payload)
            if final_error.code != 0 { return response {},final_error }
            buffered,buffer_error := std.database.buffered_rows(columns,rows)
            return response { rows: buffered, has_rows: true },buffer_error
        }
        used = used + len(payload)
        if used > client.config.max_result_bytes || len(rows) >= client.config.max_rows { return response {},_transport_error(client*,0,"MySQL buffered result limit exceeded") }
        if binary {
            row,row_error := _typed_binary_row(payload,definitions)
            if row_error.code != 0 { return response {},_fatal(client*,row_error) }
            rows = append(rows,row)
        } else {
            row,row_error := _typed_text_row(payload,definitions)
            if row_error.code != 0 { return response {},_fatal(client*,row_error) }
            rows = append(rows,row)
        }
    }
    return response {},protocol_error("unreachable result state")
}
func query(connection* client, string sql) (std.database.rows,std.database.error) {
    maximum := client.config.max_packet_bytes
    payload,error := query_command(sql,maximum)
    if error.code != 0 { return std.database.rows {},std.database.failure(error.code,error.message) }
    sent := _command(client*,payload)
    if sent.code != 0 { return std.database.rows {},sent }
    result,read_error := _read_response(client*,false)
    if read_error.code != 0 { return std.database.rows {},read_error }
    if !result.has_rows { return std.database.rows {},std.database.failure(std.database.error_invalid,"query did not return rows; use exec") }
    return result.rows,std.database.error {}
}
func exec(connection* client, string sql) (std.database.result,std.database.error) {
    maximum := client.config.max_packet_bytes
    payload,error := query_command(sql,maximum)
    if error.code != 0 { return std.database.result {},std.database.failure(error.code,error.message) }
    sent := _command(client*,payload)
    if sent.code != 0 { return std.database.result {},sent }
    result,read_error := _read_response(client*,false)
    if read_error.code != 0 { return std.database.result {},read_error }
    if result.has_rows { return std.database.result {},std.database.failure(std.database.error_invalid,"exec returned rows; use query") }
    return result.metadata,std.database.error {}
}
