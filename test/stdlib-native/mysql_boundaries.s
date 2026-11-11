package main
import ("std.database"; "std.database.wire"; "std.mysql"; "std.prelude")
func byte(int value) string { bytes,error := std.database.wire.encode_uint(value,1,true); if error.code != 0 { panic("byte fixture") }
    return bytes }
func main() int {
    text := ""
    index := 0
    while index < 251 { text = text + "x"; index = index + 1 }
    encoded, error := std.mysql.encode_length_string(text)
    if error.code != 0 || encoded != byte(252) + byte(251) + byte(0) + text { return 1 }
    minimum := std.database.value.integer(-9223372036854775808)
    minimum_packet, minimum_error := std.mysql.execute_statement_command(0,std.database.value[]{minimum},128)
    if minimum_error.code != 0 { return 2 }
    expected := byte(23) + byte(0) + byte(0) + byte(0) + byte(0) + byte(0) + byte(1) + byte(0) + byte(0) + byte(0) + byte(0) + byte(1) + byte(8) + byte(0) + byte(0) + byte(0) + byte(0) + byte(0) + byte(0) + byte(0) + byte(0) + byte(128)
    if minimum_packet != expected { return 3 }
    valid, valid_error := std.mysql.encode_packet("abc",0,1024)
    if valid_error.code != 0 { return 4 }
    index = 0
    while index < len(valid) {
        cut := std.prelude.prelude_slice(valid,0,index)
        ignored, cut_error := std.mysql.decode_packet(cut,0,1024)
        if cut_error.code == 0 { return 5 }
        index = index + 1
    }
    prepared := byte(0) + byte(1) + byte(0) + byte(0) + byte(0) + byte(0) + byte(0) + byte(0) + byte(0) + byte(0) + byte(0) + byte(0)
    index = 0
    while index < len(prepared) {
        cut := std.prelude.prelude_slice(prepared,0,index)
        ignored, cut_error := std.mysql.decode_prepare_ok(cut)
        if cut_error.code == 0 { return 6 }
        index = index + 1
    }
    // Byte eight crosses a null-bitmap boundary. Nine NULL parameters produce
    // two bitmap bytes, sixteen-bit type descriptors, and no value bytes.
    null := std.database.value.null
    nulls := std.database.value[]{null,null,null,null,null,null,null,null,null}
    null_packet, null_error := std.mysql.execute_statement_command(0,nulls,128)
    source := std.database.wire.cursor { data: null_packet, position: 10 }
    if null_error.code != 0 || std.database.wire.read_byte(source*) != 255 || std.database.wire.read_byte(source*) != 1 || std.database.wire.read_byte(source*) != 1 || len(null_packet) != 31 { return 7 }
    invalid_state := std.mysql.decode_error(byte(255) + byte(1) + byte(0) + "#23!05bad state")
    if invalid_state.code != std.database.error_protocol { return 8 }
    println("mysql boundaries: PASS")
    return 0
}
