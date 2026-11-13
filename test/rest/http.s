package main
import "std.http"
func main() int {
    request,error := std.http.parse_request("POST /api/users?q=%E4%B8%AD HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: 3\r\n\r\n{} ",std.http.options { max_body_bytes: 32 })
    if error.code != 0 || request.content_length != 3 || request.query != "q=%E4%B8%AD" || std.http.header_value(request,"content-type") != "application/json" { return 1 }
    wire,we := std.http.serialize_response(std.http.response { status: 204 },false)
    if we.code != 0 || wire != "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n" { return 2 }
    unsafe_header := std.http.header { name: "X-Unsafe", value: "x\r\ny" }
    bad,be := std.http.serialize_response(std.http.response { status: 200, headers: [unsafe_header] },false)
    if be.code == 0 { return 3 }
    return 0
}
