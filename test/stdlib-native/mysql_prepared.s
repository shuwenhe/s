package main
import ("std.database"; "std.database.wire"; "std.mysql")
func byte(int value) string { bytes,error := std.database.wire.encode_uint(value,1,true); if error.code != 0 { panic("byte fixture") }
    return bytes }
func main() int {
    null := std.database.value.null
    signed := std.database.value.integer(-1)
    text := std.database.value.text("a'?")
    binary := std.database.value.binary("a" + byte(0) + "b")
    unsigned := std.database.value.unsigned_integer("18446744073709551615")
    params := std.database.value[]{null,signed,text,binary,unsigned}
    encoded, error := std.mysql.execute_statement_command(42,params,1024)
    header := byte(23) + byte(42) + byte(0) + byte(0) + byte(0) + byte(0) + byte(1) + byte(0) + byte(0) + byte(0)
    types := byte(6) + byte(0) + byte(8) + byte(0) + byte(253) + byte(0) + byte(252) + byte(0) + byte(8) + byte(128)
    full := byte(255) + byte(255) + byte(255) + byte(255) + byte(255) + byte(255) + byte(255) + byte(255)
    if error.code != 0 || encoded != header + byte(1) + byte(1) + types + full + byte(3) + "a'?" + byte(3) + "a" + byte(0) + "b" + full { return 1 }
    empty, empty_error := std.mysql.execute_statement_command(42,std.database.value[](),1024)
    if empty_error.code != 0 || empty != header { return 2 }
    invalid := std.database.value.unsigned_integer("18446744073709551616")
    invalid_packet, invalid_error := std.mysql.execute_statement_command(42,std.database.value[]{invalid},1024)
    if invalid_error.code != std.database.error_overflow { return 3 }
    temporal := std.database.value.timestamp("2026-11-11 00:00:00")
    unsupported, unsupported_error := std.mysql.execute_statement_command(42,std.database.value[]{temporal},1024)
    if unsupported_error.code != std.database.error_unsupported { return 4 }
    bounded, bounded_error := std.mysql.execute_statement_command(42,params,10)
    if bounded_error.code == 0 { return 5 }
    prepared, prepared_error := std.mysql.decode_prepare_ok(byte(0) + byte(42) + byte(0) + byte(0) + byte(0) + byte(2) + byte(0) + byte(5) + byte(0) + byte(0) + byte(3) + byte(0))
    if prepared_error.code != 0 || prepared.statement_id != 42 || prepared.column_count != 2 || prepared.parameter_count != 5 || prepared.warning_count != 3 { return 6 }
    malformed, malformed_error := std.mysql.decode_prepare_ok(byte(0) + "bad")
    if malformed_error.code == 0 { return 7 }
    // ColumnDefinition41, six length-encoded names plus twelve fixed bytes.
    column, column_error := std.mysql.decode_column(byte(3) + "def" + byte(2) + "db" + byte(1) + "t" + byte(1) + "t" + byte(1) + "v" + byte(1) + "v" + byte(12) + byte(63) + byte(0) + byte(255) + byte(0) + byte(0) + byte(0) + byte(252) + byte(128) + byte(0) + byte(0) + byte(0) + byte(0))
    if column_error.code != 0 || column.name != "v" || column.schema != "db" || column.type_id != 252 || column.flags != 128 || column.charset != 63 { return 8 }
    switch_packet, switch_error := std.mysql.decode_auth_switch(byte(254) + "mysql_native_password" + byte(0) + "12345678abcdefghijkl" + byte(0))
    if switch_error.code != 0 || switch_packet.plugin != "mysql_native_password" || switch_packet.scramble != "12345678abcdefghijkl" { return 9 }
    println("mysql prepared packets: PASS")
    return 0
}
