package main
import ("std.database"; "std.database.wire"; "std.mysql"; "std.option")
func byte(int value) string { bytes,error := std.database.wire.encode_uint(value,1,true); if error.code != 0 { panic("byte fixture") }
    return bytes }
func main() int {
    ok, error := std.mysql.decode_ok(byte(0) + byte(2) + byte(42) + byte(2) + byte(0) + byte(3) + byte(0) + "info")
    if error.code != 0 || ok.metadata.affected_rows.unwrap() != "2" || ok.metadata.last_insert_id.unwrap() != "42" || ok.metadata.warning_count != 3 || ok.status != 2 || ok.info != "info" { return 1 }
    broken, broken_error := std.mysql.decode_ok(byte(0) + byte(251) + byte(0) + byte(0) + byte(0) + byte(0) + byte(0))
    if broken_error.code == 0 { return 2 }
    server := std.mysql.decode_error(byte(255) + byte(21) + byte(4) + "#28000Access denied")
    if server.code != std.database.error_server || server.native_code != 1045 || server.sqlstate != "28000" || server.message != "Access denied" || server.driver != "mysql" { return 3 }
    malformed := std.mysql.decode_error(byte(255) + byte(1))
    if malformed.code != std.database.error_protocol { return 4 }
    row, row_error := std.mysql.decode_text_row(byte(251) + byte(0) + byte(3) + "abc",3)
    if row_error.code != 0 || len(row.values) != 3 || !std.database.is_null(row.values[0]) || std.database.is_null(row.values[1]) { return 5 }
    extra, extra_error := std.mysql.decode_text_row(byte(0) + byte(0),1)
    cut, cut_error := std.mysql.decode_text_row(byte(5) + "x",1)
    if extra_error.code == 0 || cut_error.code == 0 { return 6 }
    query, query_error := std.mysql.query_command("SELECT 1",1024)
    prepare, prepare_error := std.mysql.prepare_command("SELECT ?",1024)
    close, close_error := std.mysql.close_statement_command(42)
    if query_error.code != 0 || query != byte(3) + "SELECT 1" || prepare_error.code != 0 || prepare != byte(22) + "SELECT ?" { return 7 }
    if close_error.code != 0 || close != byte(25) + byte(42) + byte(0) + byte(0) + byte(0) { return 8 }
    invalid, invalid_error := std.mysql.query_command("long",2)
    invalid_close, invalid_close_error := std.mysql.close_statement_command(-1)
    if invalid_error.code == 0 || invalid_close_error.code == 0 { return 9 }
    println("mysql results: PASS")
    return 0
}
