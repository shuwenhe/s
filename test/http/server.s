package main
import ("std.http"; "std.prelude"; "std.tcp")
extern "intrinsic" func runtime_env_get(string key, string fallback) string
func main() int {
    mode := runtime_env_get("S_HTTP_TEST_MODE","one")
    config := std.http.options { host: "127.0.0.1", port: 0, max_header_bytes: 512, max_request_line_bytes: 256, max_headers: 8, accept_timeout_ms: 1000, read_timeout_ms: 150, write_timeout_ms: 150 }
    if mode == "invalid" { config.read_timeout_ms = -1 }
    server,error := std.http.listen(config)
    if mode == "invalid" { if error.code != 22 || !server.closed { return 1 }; return 0 }
    if error.code != 0 { println("LISTEN ERROR " + error.message); return 2 }
    port,port_error := std.http.local_port(server*)
    if port_error.code != 0 { std.http.shutdown(server*); return 3 }
    println(std.prelude.to_string(port))
    if mode == "write-timeout" {
        connection,accept_error := std.tcp.accept(server.listener,1000)
        if accept_error.code != 0 { std.http.shutdown(server*); return 9 }
        body := "x"
        index := 0
        while index < 24 { body = body + body; index = index + 1 }
        output := std.http.response { status: 200, body: body }
        problem := std.http.write_response(connection*,output,false,40)
        std.tcp.close(connection*)
        if problem.code != 110 { std.http.shutdown(server*); return 10 }
        println("WRITE_TIMEOUT")
    } else if mode == "accept-timeout" {
        event,problem := std.http.serve_next(server*)
        if problem.code != 110 || event.status != 0 { std.http.shutdown(server*); return 4 }
    } else {
        count := 1
        if mode == "three" { count = 3 }
        if mode == "many" { count = 48 }
        index := 0
        while index < count {
            event,problem := std.http.serve_next(server*)
            if problem.code != 0 && event.status == 0 && !event.peer_eof { println(problem.message); std.http.shutdown(server*); return 5 }
            index = index + 1
        }
    }
    if std.http.shutdown(server*).code != 0 { return 6 }
    if std.http.shutdown(server*).code != 0 { return 7 }
    stopped,stopped_error := std.http.serve_next(server*)
    if stopped_error.code != 9 { return 8 }
    println("SHUTDOWN")
    return 0
}
