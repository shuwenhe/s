package main
import ("std.database"; "std.database.wire"; "std.postgresql"; "std.option")
func byte(int value) string { bytes,error := std.database.wire.encode_uint(value,1,false); if error.code != 0 { panic("byte fixture") }
    return bytes }
func main() int {
    zero := byte(0)
    frame, error := std.postgresql.encode_message(81,"SELECT 1" + zero,1024)
    if error.code != 0 || frame != "Q" + zero + zero + zero + byte(13) + "SELECT 1" + zero { return 1 }
    parsed, parse_error := std.postgresql.decode_message(frame,1024)
    if parse_error.code != 0 || parsed.tag != 81 || parsed.payload != "SELECT 1" + zero { return 2 }
    broken, broken_error := std.postgresql.decode_message("Q" + zero + zero + zero + byte(3),1024)
    if broken_error.code == 0 { return 3 }
    ssl := std.postgresql.ssl_request()
    if ssl != zero + zero + zero + byte(8) + byte(4) + byte(210) + byte(22) + byte(47) { return 4 }
    startup, startup_error := std.postgresql.startup_message("alice","db",1024)
    if startup_error.code != 0 || startup != zero + zero + zero + byte(32) + zero + byte(3) + zero + zero + "user" + zero + "alice" + zero + "database" + zero + "db" + zero + zero { return 5 }
    unsafe, unsafe_error := std.postgresql.startup_message("alice" + zero + "bad","db",1024)
    if unsafe_error.code == 0 { return 6 }
    parse, statement_error := std.postgresql.parse_message("stmt","SELECT $1",int[]{25},1024)
    if statement_error.code != 0 || parse != "P" + zero + zero + zero + byte(25) + "stmt" + zero + "SELECT $1" + zero + zero + byte(1) + zero + zero + zero + byte(25) { return 7 }
    null := std.postgresql.bound_parameter { data: option[string].none, format: 0 }
    text := std.postgresql.bound_parameter { data: option.some("a'?$1"), format: 0 }
    binary := std.postgresql.bound_parameter { data: option.some("a" + zero + "b"), format: 1 }
    bound, bind_error := std.postgresql.bind_message("","stmt",std.postgresql.bound_parameter[]{null,text,binary},1024)
    if bind_error.code != 0 { return 8 }
    message, message_error := std.postgresql.decode_message(bound,1024)
    if message_error.code != 0 || message.tag != 66 { return 9 }
    expected := zero + "stmt" + zero + zero + byte(3) + zero + zero + zero + zero + zero + byte(1) + zero + byte(3) + byte(255) + byte(255) + byte(255) + byte(255) + zero + zero + zero + byte(5) + "a'?$1" + zero + zero + zero + byte(3) + "a" + zero + "b" + zero + zero
    if message.payload != expected { return 10 }
    execute, execute_error := std.postgresql.execute_message("",0,1024)
    if execute_error.code != 0 || execute != "E" + zero + zero + zero + byte(9) + zero + zero + zero + zero + zero { return 11 }
    if std.postgresql.sync_message() != "S" + zero + zero + zero + byte(4) { return 12 }
    println("postgresql messages: PASS")
    return 0
}
