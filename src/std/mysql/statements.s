package std.mysql
import "std.database"

struct prepared_statement { int statement_id, int parameter_count, int column_count, int token, string owner, bool closed }
func _statement_valid(connection* client, prepared_statement* statement) std.database.error {
    if client.closed || statement.closed { return std.database.failure(std.database.error_closed,"MySQL connection or statement is closed") }
    if statement.owner != client.identity { return std.database.failure(std.database.error_invalid,"statement belongs to another MySQL connection") }
    index := 0
    while index < len(client.active_statement_tokens) {
        if client.active_statement_tokens[index] == statement.token { return std.database.error {} }
        index = index + 1
    }
    return std.database.failure(std.database.error_closed,"MySQL statement was already closed")
}
func _prepare_metadata(connection* client, int count) std.database.error {
    if count == 0 { return std.database.error {} }
    index := 0
    total := 0
    while index < count {
        payload,error := _read_packet(client*)
        if error.code != 0 { return error }
        total = total + len(payload)
        if total > client.config.max_result_bytes { return _transport_error(client*,0,"prepared metadata exceeds result limit") }
        definition,problem := decode_column(payload)
        if problem.code != 0 { return _fatal(client*,problem) }
        index = index + 1
    }
    separator,error := _read_packet(client*)
    if error.code != 0 { return error }
    return _eof(client*,separator)
}
func prepare(connection* client, string sql) (prepared_statement,std.database.error) {
    if len(client.active_statement_tokens) >= 1024 { return prepared_statement { closed: true },std.database.failure(std.database.error_bounds,"too many live prepared statements") }
    maximum := client.config.max_packet_bytes
    command,error := prepare_command(sql,maximum)
    if error.code != 0 { return prepared_statement { closed: true },std.database.failure(error.code,error.message) }
    sent := _command(client*,command)
    if sent.code != 0 { return prepared_statement { closed: true },sent }
    payload,read_error := _read_packet(client*)
    if read_error.code != 0 { return prepared_statement { closed: true },read_error }
    if len(payload) > 0 && std.database._byte(payload,0) == 255 { return prepared_statement { closed: true },_server_error(client*,payload) }
    info,problem := decode_prepare_ok(payload)
    if problem.code != 0 { return prepared_statement { closed: true },_fatal(client*,problem) }
    parameter_error := _prepare_metadata(client*,info.parameter_count)
    if parameter_error.code != 0 { return prepared_statement { closed: true },parameter_error }
    column_error := _prepare_metadata(client*,info.column_count)
    if column_error.code != 0 { return prepared_statement { closed: true },column_error }
    if client.next_statement_token == 9223372036854775807 { return prepared_statement { closed: true },_transport_error(client*,0,"statement generation exhausted") }
    client.next_statement_token = client.next_statement_token + 1
    client.active_statement_tokens = append(client.active_statement_tokens,client.next_statement_token)
    return prepared_statement { statement_id: info.statement_id, parameter_count: info.parameter_count, column_count: info.column_count, token: client.next_statement_token, owner: client.identity },std.database.error {}
}
func _statement_execute(connection* client, prepared_statement* statement, std.database.value[] parameters) (response,std.database.error) {
    validation := _statement_valid(client*,statement*)
    if validation.code != 0 { return response {},validation }
    if len(parameters) != statement.parameter_count { return response {},std.database.failure(std.database.error_invalid,"MySQL prepared parameter count mismatch") }
    maximum := client.config.max_packet_bytes
    id := statement.statement_id
    payload,error := execute_statement_command(id,parameters,maximum)
    if error.code != 0 { return response {},std.database.failure(error.code,error.message) }
    sent := _command(client*,payload)
    if sent.code != 0 { return response {},sent }
    return _read_response(client*,true)
}
func statement_query(connection* client, prepared_statement* statement, std.database.value[] parameters) (std.database.rows,std.database.error) {
    result,error := _statement_execute(client*,statement*,parameters)
    if error.code != 0 { return std.database.rows {},error }
    if !result.has_rows { return std.database.rows {},std.database.failure(std.database.error_invalid,"prepared query did not return rows") }
    return result.rows,std.database.error {}
}
func statement_exec(connection* client, prepared_statement* statement, std.database.value[] parameters) (std.database.result,std.database.error) {
    result,error := _statement_execute(client*,statement*,parameters)
    if error.code != 0 { return std.database.result {},error }
    if result.has_rows { return std.database.result {},std.database.failure(std.database.error_invalid,"prepared exec returned rows") }
    return result.metadata,std.database.error {}
}
func close_statement(connection* client, prepared_statement* statement) std.database.error {
    if statement.closed { return std.database.error {} }
    validation := _statement_valid(client*,statement*)
    if validation.code != 0 { return validation }
    id := statement.statement_id
    payload,error := close_statement_command(id)
    if error.code != 0 { return error }
    sent := _command(client*,payload)
    if sent.code != 0 { return sent }
    remaining := int[]()
    index := 0
    while index < len(client.active_statement_tokens) {
        token := client.active_statement_tokens[index]
        if token != statement.token { remaining = append(remaining,token) }
        index = index + 1
    }
    client.active_statement_tokens = remaining
    statement.closed = true
    return std.database.error {}
}
func begin(connection* client) std.database.error {
    if client.in_transaction { return std.database.failure(std.database.error_invalid,"MySQL transaction already active") }
    metadata,error := exec(client*,"START TRANSACTION")
    return error
}
func commit(connection* client) std.database.error {
    if client.closed { return std.database.failure(std.database.error_closed,"MySQL connection is closed") }
    if !client.in_transaction { return std.database.failure(std.database.error_invalid,"no MySQL transaction is active") }
    metadata,error := exec(client*,"COMMIT")
    return error
}
func rollback(connection* client) std.database.error {
    if client.closed { return std.database.failure(std.database.error_closed,"MySQL connection is closed") }
    if !client.in_transaction { return std.database.failure(std.database.error_invalid,"no MySQL transaction is active") }
    metadata,error := exec(client*,"ROLLBACK")
    return error
}
