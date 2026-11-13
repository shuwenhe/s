package std.http
import "std.tcp"

// The returned pending owns its socket, including on HTTP parse failures.
// Transport/accept failures return a closed pending. Always respond or discard.
func receive(server* value) (pending,http_error) {
    if value.closed { return pending { closed: true },http_error { code: 9, message: "server closed" } }
    config := value.config
    connection,accept_error := std.tcp.accept(value.listener,config.accept_timeout_ms)
    if accept_error.code != 0 { return pending { closed: true },http_error { code: accept_error.code, message: accept_error.operation } }
    parsed,error := _read_request(connection*,config)
    if error.status == 0 && (error.code != 0 || error.message == "EOF") {
        std.tcp.close(connection*)
        return pending { closed: true, accepted: true },error
    }
    return pending { connection: connection, request: parsed, config: config, accepted: true },error
}
func discard(pending* value) http_error {
    if value.closed { return http_error {} }
    error := std.tcp.close(value.connection*)
    value.closed = true
    return http_error { code: error.code, message: error.operation }
}
func respond(pending* value, response reply) http_error {
    if value.closed { return http_error { code: 9, message: "exchange closed" } }
    request := value.request
    config := value.config
    head := request.method == "HEAD"
    timeout := config.write_timeout_ms
    error := write_response(value.connection*,reply,head,timeout)
    closed := discard(value*)
    if error.code != 0 { return error }
    return closed
}
