package main
import "std.http"
func bad(string raw, int status) bool {
    request,error := std.http.parse_request(raw,std.http.options {})
    return error.code != 0 && error.status == status
}
func main() int {
    request,error := std.http.parse_request("GET /health?probe=1 HTTP/1.1\r\nhOsT: localhost:8080\r\nContent-Length: 0\r\n\r\n",std.http.options {})
    if error.code != 0 || request.method != "GET" || request.path != "/health" || request.host != "localhost:8080" { return 1 }
    response := std.http.route(request)
    wire,we := std.http.serialize_response(response,false)
    if we.code != 0 || wire != "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 15\r\nConnection: close\r\n\r\n{\"status\":\"ok\"}" { return 2 }
    unicode,ue := std.http.serialize_response(std.http.response { status: 200, body: "你好" },false)
    if ue.code != 0 || unicode != "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 6\r\nConnection: close\r\n\r\n你好" { return 3 }
    if !bad("GET / HTTP/1.1\r\n\r\n",400) { return 4 }
    if !bad("GET / HTTP/1.1\nHost: x\n\n",400) { return 5 }
    if !bad("GET / HTTP/1.1\r\nHost: x\r\nHost: y\r\n\r\n",400) { return 6 }
    if !bad("GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n",400) { return 7 }
    if !bad("GET / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nContent-Length: 0\r\n\r\n",400) { return 8 }
    if !bad("GET / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n",501) { return 9 }
    if !bad("GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 1\r\n\r\n",413) { return 10 }
    if !bad("GET /bad%GG HTTP/1.1\r\nHost: x\r\n\r\n",400) { return 11 }
    if !bad("GET /#x HTTP/1.1\r\nHost: x\r\n\r\n",400) { return 12 }
    invalid,ie := std.http.serialize_response(std.http.response { status: 999, body: "x" },false)
    if ie.code == 0 { return 13 }
    println("PASS native HTTP protocol")
    return 0
}
