package main
import ("std.database"; "std.database.wire"; "std.mysql")
func byte(int value) string { bytes,error := std.database.wire.encode_uint(value,1,true); if error.code != 0 { panic("byte fixture") }
    return bytes }
func main() int {
    encoded, error := std.mysql.encode_packet("abc",7,1024)
    if error.code != 0 || encoded != byte(3) + byte(0) + byte(0) + byte(7) + "abc" { return 1 }
    packet, packet_error := std.mysql.decode_packet(encoded,7,1024)
    if packet_error.code != 0 || packet.sequence != 7 || packet.payload != "abc" { return 2 }
    wrong, wrong_error := std.mysql.decode_packet(encoded,8,1024)
    small, small_error := std.mysql.decode_packet(encoded,7,2)
    truncated, truncated_error := std.mysql.decode_packet(byte(3) + byte(0) + byte(0) + byte(7) + "ab",7,1024)
    if wrong_error.code == 0 || small_error.code == 0 || truncated_error.code == 0 { return 3 }
    bad, bad_error := std.mysql.encode_packet("x",256,1024)
    if bad_error.code == 0 { return 4 }
    source := std.database.wire.cursor { data: byte(250) + byte(251) + byte(252) + byte(255) + byte(255) + byte(253) + byte(0) + byte(0) + byte(1) }
    first := std.mysql.read_lenenc(source*)
    null := std.mysql.read_lenenc(source*)
    short := std.mysql.read_lenenc(source*)
    medium := std.mysql.read_lenenc(source*)
    if source.code != 0 || first.number != "250" || first.is_null || !null.is_null || short.number != "65535" || medium.number != "65536" { return 5 }
    maximum := std.database.wire.cursor { data: byte(254) + byte(255) + byte(255) + byte(255) + byte(255) + byte(255) + byte(255) + byte(255) + byte(255) }
    full := std.mysql.read_lenenc(maximum*)
    if maximum.code != 0 || full.number != "18446744073709551615" { return 6 }
    invalid := std.database.wire.cursor { data: byte(255) }
    invalid_length := std.mysql.read_lenenc(invalid*)
    if invalid.code == 0 { return 7 }
    cut := std.database.wire.cursor { data: byte(254) + "abc" }
    cut_length := std.mysql.read_lenenc(cut*)
    if cut.code == 0 { return 8 }
    fields := std.database.wire.cursor { data: byte(0) + byte(251) + byte(3) + "a" + byte(0) + "b" }
    empty := std.mysql.read_field(fields*)
    absent := std.mysql.read_field(fields*)
    binary := std.mysql.read_field(fields*)
    if fields.code != 0 || !empty.is_some() || empty.unwrap() != "" || !absent.is_none() || binary.unwrap() != "a" + byte(0) + "b" { return 9 }
    excessive := std.database.wire.cursor { data: byte(254) + byte(255) + byte(255) + byte(255) + byte(255) + byte(255) + byte(255) + byte(255) + byte(255) }
    impossible := std.mysql.read_field(excessive*)
    if excessive.code == 0 { return 10 }
    println("mysql packets: PASS")
    return 0
}
