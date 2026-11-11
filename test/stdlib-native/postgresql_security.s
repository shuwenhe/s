package main
import ("std.database"; "std.database.wire"; "std.postgresql")
func byte(int value) string { bytes,error := std.database.wire.encode_uint(value,1,false); if error.code != 0 { panic("byte fixture") }
    return bytes }
func main() int {
    zero := byte(0)
    // Error field order is unspecified; V is the nonlocalized severity.
    fatal := std.postgresql.decode_error("VFATAL" + zero + "Slocalized fatal" + zero + "C28000" + zero + "Mdenied" + zero + zero)
    if fatal.code != std.database.error_server || !fatal.fatal { return 1 }
    fatal_reversed := std.postgresql.decode_error("Slocalized fatal" + zero + "VFATAL" + zero + "C28000" + zero + "Mdenied" + zero + zero)
    if fatal_reversed.code != std.database.error_server || !fatal_reversed.fatal { return 2 }
    nonfatal := std.postgresql.decode_error("SFATAL" + zero + "VERROR" + zero + "C23505" + zero + "Mduplicate" + zero + zero)
    if nonfatal.code != std.database.error_server || nonfatal.fatal { return 3 }
    malformed := std.postgresql.decode_error("SERROR" + zero + "C23!05" + zero + "Mbad state" + zero + zero)
    if malformed.code != std.database.error_protocol { return 4 }
    duplicate := std.postgresql.decode_error("SERROR" + zero + "VERROR" + zero + "VFATAL" + zero + "C23505" + zero + "Mbad severity" + zero + zero)
    if duplicate.code != std.database.error_protocol { return 5 }
    println("postgresql error security: PASS")
    return 0
}
