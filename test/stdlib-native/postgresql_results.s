package main
import ("std.database"; "std.database.wire"; "std.postgresql"; "std.option")
func byte(int value) string { bytes,error := std.database.wire.encode_uint(value,1,false); if error.code != 0 { panic("byte fixture") }
    return bytes }
func main() int {
    zero := byte(0)
    columns, error := std.postgresql.decode_row_description(zero + byte(1) + "v" + zero + zero + zero + zero + byte(42) + zero + byte(1) + zero + zero + zero + byte(25) + byte(255) + byte(255) + byte(255) + byte(255) + byte(255) + byte(255) + zero + zero)
    if error.code != 0 || len(columns) != 1 || columns[0].name != "v" || columns[0].type_oid != 25 || columns[0].table_oid != 42 || columns[0].attribute_number != 1 || columns[0].type_size != -1 || columns[0].type_modifier != -1 { return 1 }
    absent, absent_error := std.postgresql.decode_data_row(zero + byte(1) + byte(255) + byte(255) + byte(255) + byte(255),columns)
    empty, empty_error := std.postgresql.decode_data_row(zero + byte(1) + zero + zero + zero + zero,columns)
    if absent_error.code != 0 || empty_error.code != 0 || !std.database.is_null(absent.values[0]) || std.database.is_null(empty.values[0]) { return 2 }
    malformed, malformed_error := std.postgresql.decode_data_row(zero + byte(1) + byte(255) + byte(255) + byte(255) + byte(254),columns)
    if malformed_error.code == 0 { return 3 }
    server := std.postgresql.decode_error("SERROR" + zero + "C23505" + zero + "Mduplicate" + zero + "Ddetail" + zero + zero)
    if server.code != std.database.error_server || server.sqlstate != "23505" || server.message != "duplicate" || server.driver != "postgresql" { return 4 }
    broken := std.postgresql.decode_error("Munterminated")
    if broken.code != std.database.error_protocol { return 5 }
    idle, idle_error := std.postgresql.decode_ready("I")
    active, active_error := std.postgresql.decode_ready("T")
    failed, failed_error := std.postgresql.decode_ready("E")
    invalid, invalid_error := std.postgresql.decode_ready("X")
    if idle_error.code != 0 || active_error.code != 0 || failed_error.code != 0 || invalid_error.code == 0 { return 6 }
    if idle != std.postgresql.transaction_status.idle || active != std.postgresql.transaction_status.active || failed != std.postgresql.transaction_status.failed { return 7 }
    accepted, accepted_error := std.postgresql.decode_authentication(zero + zero + zero + zero)
    cleartext, cleartext_error := std.postgresql.decode_authentication(zero + zero + zero + byte(3))
    md5, md5_error := std.postgresql.decode_authentication(zero + zero + zero + byte(5) + "salt")
    if accepted_error.code != 0 || accepted.kind != 0 || cleartext_error.code != 0 || cleartext.kind != 3 || md5_error.code != 0 || md5.data != "salt" { return 8 }
    malformed_auth, malformed_auth_error := std.postgresql.decode_authentication(zero + zero + zero + byte(5) + "bad")
    if malformed_auth_error.code == 0 { return 9 }
    complete, complete_error := std.postgresql.decode_command_complete("INSERT 0 42" + zero)
    if complete_error.code != 0 || complete.affected_rows.unwrap() != "42" || complete.command_tag != "INSERT 0 42" || !complete.last_insert_id.is_none() { return 10 }
    ddl, ddl_error := std.postgresql.decode_command_complete("CREATE TABLE" + zero)
    if ddl_error.code != 0 || !ddl.affected_rows.is_none() { return 11 }
    parameter, parameter_error := std.postgresql.decode_parameter_status("server_version" + zero + "16.0" + zero)
    if parameter_error.code != 0 || parameter.name != "server_version" || parameter.value != "16.0" { return 12 }
    println("postgresql results: PASS")
    return 0
}
