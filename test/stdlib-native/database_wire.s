package main
import ("std.database"; "std.database.wire")
func main() int {
    encoded, error := std.database.wire.encode_uint(66051,4,true)
    if error.code != 0 { return 1 }
    source := std.database.wire.cursor { data: encoded }
    if std.database.wire.read_byte(source*) != 3 || std.database.wire.read_byte(source*) != 2 || std.database.wire.read_byte(source*) != 1 || std.database.wire.read_byte(source*) != 0 { return 2 }
    source.position = 0
    if std.database.wire.read_uint(source*,4,true) != 66051 || source.code != 0 { return 3 }
    source.position = 0
    if std.database.wire.read_uint(source*,4,false) != 50462976 { return 4 }
    if std.database.wire.read_byte(source*) != 0 || source.code != std.database.error_protocol || source.position != 4 { return 5 }
    source.position = 0
    if std.database.wire.read_byte(source*) != 0 || source.position != 0 { return 6 }
    zero, zero_error := std.database.wire.encode_uint(0,1,true)
    if zero_error.code != 0 || len(zero) != 1 { return 7 }
    text := std.database.wire.cursor { data: "hello" + zero + "tail" }
    if std.database.wire.read_cstring(text*) != "hello" || text.code != 0 || text.position != 6 { return 8 }
    if std.database.wire.read_bytes(text*,4) != "tail" || text.code != 0 { return 9 }
    missing := std.database.wire.cursor { data: "unterminated" }
    if std.database.wire.read_cstring(missing*) != "" || missing.code == 0 || missing.position != 0 { return 10 }
    invalid := std.database.wire.cursor { data: "a", position: -1 }
    if std.database.wire.read_byte(invalid*) != 0 || invalid.code == 0 { return 11 }
    oversized := std.database.wire.cursor { data: "abc", position: 1 }
    if std.database.wire.read_bytes(oversized*,9223372036854775807) != "" || oversized.code == 0 || oversized.position != 1 { return 12 }
    negative, negative_error := std.database.wire.encode_uint(-1,4,true)
    overflow, overflow_error := std.database.wire.encode_uint(256,1,true)
    if negative_error.code == 0 || overflow_error.code == 0 { return 13 }
    high, high_error := std.database.wire.encode_uint(255,1,true)
    if high_error.code != 0 { return 14 }
    maximum := std.database.wire.cursor { data: high + high + high + high + high + high + high + high }
    if std.database.wire.read_uint_decimal(maximum*,8,true) != "18446744073709551615" || maximum.code != 0 { return 15 }
    maximum.position = 0
    if std.database.wire.read_uint(maximum*,8,true) != 0 || maximum.code != std.database.error_overflow { return 16 }
    truncated := std.database.wire.cursor { data: "abc" }
    if std.database.wire.read_uint_decimal(truncated*,8,true) != "" || truncated.code == 0 { return 17 }
    width := std.database.wire.cursor { data: "abc" }
    if std.database.wire.read_uint(width*,0,true) != 0 || width.code == 0 { return 18 }
    println("database wire: PASS")
    return 0
}
