package main
import ("std.http"; "std.prelude")
extern "intrinsic" func runtime_env_get(string key,string fallback) string
func main() int {
    mode := runtime_env_get("S_REST_TEST_MODE","one")
    config := std.http.options {host:"127.0.0.1",port:0,max_body_bytes:32,max_header_bytes:512,max_request_line_bytes:256,max_headers:16,accept_timeout_ms:2000,read_timeout_ms:150,write_timeout_ms:150}
    server,error := std.http.listen(config)
    if error.code != 0 { return 1 }
    port,pe := std.http.local_port(server*)
    if pe.code != 0 { std.http.shutdown(server*); return 2 }
    println(std.prelude.to_string(port))
    count := 1
    if mode == "many" { count = 24 }
    if mode == "two" { count = 2 }
    i := 0
    while i < count {
        event,problem := std.http.receive(server*)
        if !event.closed {
            parsed := event.request
            output := std.http.response {status:200,body:parsed.body,content_type:"application/json"}
            if parsed.body == "" { output.body = "{}" }
            if parsed.path == "/inspect" { output.body = parsed.query + "|" + std.http.header_value(parsed,"X-Probe"); output.content_type = "text/plain" }
            if problem.code != 0 { output.status = problem.status; output.body = "{}" }
            if parsed.path == "/unsafe" {
                bad := std.http.header {name:"X-Test",value:"a\r\nb"}
                output.headers = [bad]
            }
            sent := std.http.respond(event*,output)
            if !event.closed { std.http.shutdown(server*); return 3 }
            discarded := std.http.discard(event*)
            if discarded.code != 0 { std.http.shutdown(server*); return 4 }
            if parsed.path == "/unsafe" && sent.code == 0 { std.http.shutdown(server*); return 5 }
        }
        i = i+1
    }
    closed := std.http.shutdown(server*)
    again := std.http.shutdown(server*)
    if closed.code != 0 || again.code != 0 { return 6 }
    println("SHUTDOWN")
    return 0
}
