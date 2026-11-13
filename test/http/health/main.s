package main
import ("std.http"; "std.tcp"; "std.prelude")
extern "intrinsic" func runtime_env_get(string key, string fallback) string
func main() int {
    text := runtime_env_get("S_HTTP_PORT","8080")
    if len(text) < 1 || len(text) > 5 { println("invalid S_HTTP_PORT"); return 1 }
    port := 0
    index := 0
    while index < len(text) {
        byte,error := std.tcp.byte_at(text,index)
        if error.code != 0 || byte < 48 || byte > 57 { println("invalid S_HTTP_PORT"); return 1 }
        port = port * 10 + byte - 48
        index = index + 1
    }
    if port > 65535 { println("invalid S_HTTP_PORT"); return 1 }
    config := std.http.options { host: "127.0.0.1", port: port }
    server,error := std.http.listen(config)
    if error.code != 0 { println(error.message); return 2 }
    actual,port_error := std.http.local_port(server*)
    if port_error.code != 0 { std.http.shutdown(server*); return 3 }
    println(std.prelude.to_string(actual))
    once := runtime_env_get("S_HTTP_ONCE","") == "1"
    while true {
        event,problem := std.http.serve_next(server*)
        if problem.code == 110 && event.status == 0 { continue }
        if problem.code != 0 && event.status == 0 && !event.peer_eof {
            println(problem.message)
            std.http.shutdown(server*)
            return 4
        }
        if once { break }
    }
    if std.http.shutdown(server*).code != 0 { return 5 }
    println("SHUTDOWN")
    return 0
}
