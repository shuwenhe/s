package main
import ("std.http"; "std.tcp")
func read(std.tcp.socket* connection, std.http.options config) (std.http.request,std.http.http_error) {
    data := ""
    while true {
        if len(data) > 0 { return std.http.parse_request(data,config) }
        chunk,error := std.tcp.read_some(connection*,64,1)
        if error.code != 0 { return std.http.request {},std.http.http_error { code: error.code } }
        data = data + chunk.data
    }
    return std.http.request {},std.http.http_error {}
}
func main() int {
    connection := std.tcp.socket { closed: true, descriptor: -1 }
    request,error := read(connection*,std.http.options {})
    if error.code != 9 { return 1 }
    return 0
}
