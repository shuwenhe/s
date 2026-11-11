package main
import ("std.database"; "std.database.wire"; "std.postgresql"; "std.option")
func main() int {
    counts := int[]{32768,65535,65536}
    test := 0
    while test < len(counts) {
        count := counts[test]
        types := make([]int,count)
        encoded, error := std.postgresql.parse_message("","SELECT 1",types,1048576)
        if count <= 65535 {
            if error.code != 0 { return 1 }
            frame, frame_error := std.postgresql.decode_message(encoded,1048576)
            if frame_error.code != 0 || len(frame.payload) != 12 + count * 4 { return 2 }
            source := std.database.wire.cursor { data: frame.payload, position: 10 }
            if std.database.wire.read_uint(source*,2,false) != count { return 3 }
        } else { if error.code != std.database.error_invalid { return 4 } }
        parameters := make([]std.postgresql.bound_parameter,count)
        null := std.postgresql.bound_parameter { data: option[string].none, format: 0 }
        index := 0
        while index < count { parameters[index] = null; index = index + 1 }
        bound, bind_error := std.postgresql.bind_message("","",parameters,1048576)
        if count <= 65535 {
            if bind_error.code != 0 { return 5 }
            frame, frame_error := std.postgresql.decode_message(bound,1048576)
            if frame_error.code != 0 || len(frame.payload) != 8 + count * 6 { return 6 }
        } else { if bind_error.code != std.database.error_invalid { return 7 } }
        test = test + 1
    }
    println("postgresql parameter limits: PASS")
    return 0
}
