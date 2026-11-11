package main
import ("std.database"; "std.database.wire"; "std.mysql"; "std.prelude")
func byte(int value) string { bytes,error := std.database.wire.encode_uint(value,1,true); if error.code != 0 { panic("byte fixture") }
    return bytes }
func greeting() string {
    zero := byte(0)
    // protocol 4.1, secure connection, plugin auth, server connection id 42.
    return byte(10) + "8.0.36" + zero + byte(42) + zero + zero + zero + "12345678" + zero + byte(0) + byte(130) + byte(45) + byte(2) + zero + byte(8) + zero + byte(21) + zero + zero + zero + zero + zero + zero + zero + zero + zero + zero + "abcdefghijkl" + zero + "caching_sha2_password" + zero
}
func main() int {
    source := greeting()
    handshake, error := std.mysql.decode_handshake(source)
    if error.code != 0 { return 1 }
    if handshake.server_version != "8.0.36" || handshake.connection_id != 42 || handshake.charset != 45 || handshake.status != 2 { return 2 }
    if handshake.capabilities != 557568 || handshake.auth_plugin != "caching_sha2_password" || handshake.scramble != "12345678abcdefghijkl" { return 3 }
    index := 0
    while index < len(source) {
        broken, broken_error := std.mysql.decode_handshake(std.prelude.prelude_slice(source,0,index))
        if broken_error.code == 0 { return 4 }
        index = index + 1
    }
    old, old_error := std.mysql.decode_handshake(byte(9) + "old" + byte(0))
    if old_error.code != std.database.error_unsupported { return 5 }
    println("mysql handshake: PASS")
    return 0
}
