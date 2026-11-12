package std.mysql
import ("std.database"; "std.crypto")

func auth_response(string plugin, string password, string scramble) (string,std.database.error) {
    if plugin != "mysql_native_password" && plugin != "caching_sha2_password" {
        return "",std.database.failure(std.database.error_unsupported,"unsupported MySQL authentication plugin")
    }
    if len(scramble) != 20 { return "",std.database.failure(std.database.error_authentication,"invalid authentication scramble") }
    if len(password) > 4096 { return "",std.database.failure(std.database.error_invalid,"password exceeds 4096 bytes") }
    if len(password) == 0 { return "",std.database.error {} }
    first := ""
    final := ""
    if plugin == "mysql_native_password" {
        one,e1 := std.crypto.sha1(password)
        two,e2 := std.crypto.sha1(one)
        three,e3 := std.crypto.sha1(scramble + two)
        if e1.code != 0 || e2.code != 0 || e3.code != 0 { return "",std.database.failure(std.database.error_authentication,"SHA-1 failed") }
        first = one
        final = three
    } else {
        one,e1 := std.crypto.sha256(password)
        two,e2 := std.crypto.sha256(one)
        three,e3 := std.crypto.sha256(two + scramble)
        if e1.code != 0 || e2.code != 0 || e3.code != 0 { return "",std.database.failure(std.database.error_authentication,"SHA-256 failed") }
        first = one
        final = three
    }
    output := ""
    index := 0
    while index < len(first) {
        output = output + std.database.__std_byte_string(std.database._byte(first,index) ^ std.database._byte(final,index))
        index = index + 1
    }
    return output,std.database.error {}
}
