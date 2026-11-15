package main
import ("std.kafka"; "std.time")
extern "intrinsic" func host_args() string[]
func main() int {
    args := host_args()
    if len(args) != 2 { return 99 }
    mode := args[1]
    b, connection_error := std.kafka.broker_connect("127.0.0.1", 19092, "consumer-fault", 1000)
    if mode == "refused" {
        if connection_error.code != std.kafka.error_transport || connection_error.native_code != 111 { return 1 }
        println("Consumer connection refusal: PASS"); return 0
    }
    if connection_error.code != 0 { return 2 }
    link := std.kafka.consumer_link { connection: b }
    rounds := 1
    if mode == "valid" { rounds = 2 }
    round := 0
    while round < rounds {
        request := std.kafka.broker_build_api_versions_request("consumer-fault", round + 1)
        if mode == "valid" && round == 0 {
            padding := "x"
            j := 0
            while j < 17 { padding = padding + padding; j = j + 1 }
            request = request + padding
        }
        timeout := 1000
        if mode == "timeout" || mode == "slow" || mode == "decode-timeout" { timeout = 100 }
        issue := std.kafka.consumer_exchange_begin(link*, request, timeout)
        if issue.code != 0 { return 3 }
        start, clock_error := std.time.monotonic_clock()
        step_error := std.kafka.consumer_exchange_step(link*, 0)
        if mode == "valid" && round == 0 {
            if link.write_position <= 0 || link.write_position >= len(request) + 4 { return 4 }
        }
        while link.state != 4 && link.problem.code == 0 {
            std.kafka.consumer_exchange_step(link*, 1)
        }
        end, end_error := std.time.monotonic_clock()
        if clock_error.code != 0 || end_error.code != 0 { return 5 }
        if mode == "valid" {
            versions, problem := std.kafka.broker_parse_api_versions_response(link.body)
            if link.problem.code != 0 || problem.code != 0 || len(versions) != 1 || link.connection.correlation_id != round + 2 { return 6 }
        } else if mode == "decode-timeout" {
            if link.problem.code != 0 && link.problem.code != std.kafka.error_timeout { return 7 }
            if link.problem.code == 0 && len(link.body) != 32768 { return 8 }
        } else {
            if link.problem.code == 0 || !link.problem.fatal || link.connection.state != 0 { return 9 }
            if mode == "timeout" || mode == "slow" {
                if link.problem.code != std.kafka.error_timeout || end - start < 50000000 || end - start > 800000000 { return 10 }
            }
            if mode == "mismatch" || mode == "short" || mode == "negative" {
                if link.problem.code != std.kafka.error_protocol { return 11 }
            }
            if mode == "oversize" && link.problem.code != std.kafka.error_bounds { return 12 }
        }
        round = round + 1
    }
    if std.kafka.consumer_link_close(link*).code != 0 || std.kafka.consumer_link_close(link*).code != 0 { return 13 }
    println("Consumer incremental fault " + mode + ": PASS")
    return 0
}
