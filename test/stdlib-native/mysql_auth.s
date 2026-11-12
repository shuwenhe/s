package main
import ("std.mysql"; "std.crypto"; "std.database")
func main() int {
    native,error := std.mysql.auth_response("mysql_native_password","password","12345678901234567890")
    if error.code != 0 || std.crypto.hex(native) != "1957dce2724282e018f40d905824cb6361f88d41" { return 1 }
    sha,error2 := std.mysql.auth_response("caching_sha2_password","password","12345678901234567890")
    if error2.code != 0 || std.crypto.hex(sha) != "718d80fb92b693f7ee1fcad95bfe7a2be1f332ac2c3ec6cdc85893b65b240650" { return 2 }
    empty,error3 := std.mysql.auth_response("caching_sha2_password","","12345678901234567890")
    if error3.code != 0 || len(empty) != 0 { return 3 }
    bad,error4 := std.mysql.auth_response("unknown","password","12345678901234567890")
    if error4.code != std.database.error_unsupported { return 4 }
    short,error5 := std.mysql.auth_response("mysql_native_password","password","short")
    if error5.code == 0 { return 5 }
    return 0
}
