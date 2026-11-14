package main
import ("std.kafka"; "std.tcp"; "std.time"; "std.prelude")
extern "intrinsic" func host_args() string[]
func main() int {
    args := host_args()
    if len(args) != 2 { return 99 }
    mode := args[1]
    if mode == "write-timeout" {
        socket, dial_error := std.tcp.dial_ipv4("127.0.0.1", 19092, 1000)
        if dial_error.code != 0 { return 30 }
        data := "x"
        i := 0
        while i < 24 { data = data + data; i = i + 1 }
        count, problem := std.tcp.write_all(socket*, data, 100)
        closed := std.tcp.close(socket*)
        if problem.code != 110 || count >= len(data) || closed.code != 0 { return 31 }
        println("TCP partial write and write timeout: PASS")
        return 0
    }
    b, connection_error := std.kafka.broker_connect("127.0.0.1", 19092, "fault-test", 1000)
    if mode == "refused" {
        if connection_error.code != std.kafka.error_transport || connection_error.native_code != 111 || b.state != 0 { return 1 }
        println("Kafka connection refusal: PASS")
        return 0
    }
    if connection_error.code != 0 { return 2 }
    if b.state != 2 || b.socket_descriptor < 0 || b.correlation_id != 1 { return 3 }
    request := std.kafka.broker_build_api_versions_request(b.client_id, b.correlation_id)
    if mode == "valid" {
        padding := "x"
        i := 0
        while i < 17 { padding = padding + padding; i = i + 1 }
        request = request + padding
        // Invalid caller input must not consume correlation or close a good socket.
        ignored, invalid := std.kafka.broker_send_request(b*, request, 0)
        if invalid.code != std.kafka.error_invalid || b.state != 2 || b.correlation_id != 1 { return 4 }
        wrong := std.kafka.broker_build_api_versions_request(b.client_id, 2)
        ignored_again, wrong_error := std.kafka.broker_send_request(b*, wrong, 1000)
        if wrong_error.code != std.kafka.error_invalid || b.correlation_id != 1 { return 5 }
    }
    timeout := 1000
    if mode == "timeout" || mode == "slow" || mode == "decode-timeout" { timeout = 100 }
    start, clock_error := std.time.monotonic_clock()
    body, problem := std.kafka.broker_send_request(b*, request, timeout)
    end, end_error := std.time.monotonic_clock()
    if clock_error.code != 0 || end_error.code != 0 { return 6 }
    if mode == "valid" {
        if problem.code != 0 || b.correlation_id != 2 { println("request error: " + problem.message); println(std.prelude.to_string(problem.code)); println(std.prelude.to_string(b.correlation_id)); return 7 }
        versions, parse_error := std.kafka.broker_parse_api_versions_response(body)
        if parse_error.code != 0 || len(versions) != 1 || versions[0].api_key != 18 { return 8 }
        // A second round trip proves correlation advances and the stream stays aligned.
        versions2, negotiation_error := std.kafka.broker_api_versions(b*, 1000)
        if negotiation_error.code != 0 || len(versions2) != 1 || b.correlation_id != 3 { return 9 }
    } else if mode == "decode-timeout" {
        // Native conversion may fit the budget; seed conversion previously
        // returned success several seconds after the 100 ms deadline.
        if end - start > 150000000 && problem.code != std.kafka.error_timeout { return 17 }
        if problem.code == 0 {
            if len(body) != 32768 { return 18 }
        } else {
            if problem.code != std.kafka.error_timeout || !problem.fatal || b.state != 0 { return 19 }
        }
    } else {
        if problem.code == 0 || !problem.fatal || b.state != 0 || b.socket_descriptor != -1 { return 10 }
        if mode == "timeout" || mode == "slow" {
            if problem.code != std.kafka.error_timeout || problem.native_code != 110 { return 11 }
            if end - start < 50000000 || end - start > 800000000 { return 12 }
        }
        if mode == "mismatch" || mode == "negative" || mode == "short" {
            if problem.code != std.kafka.error_protocol { return 13 }
        }
        if mode == "oversize" && problem.code != std.kafka.error_bounds { return 14 }
        if mode == "eof-header" || mode == "eof-body" {
            if problem.code != std.kafka.error_transport { return 15 }
        }
    }
    first_close := std.kafka.broker_close(b*)
    second_close := std.kafka.broker_close(b*)
    if first_close.code != 0 || second_close.code != 0 || b.state != 0 || b.socket_descriptor != -1 { return 16 }
    println("Kafka fault " + mode + ": PASS")
    return 0
}
