package main
import ("std.kafka"; "std.time")
extern "intrinsic" func host_args() string[]
func main() int {
    args := host_args()
    if len(args) != 2 { return 99 }
    mode := args[1]
    p, problem := std.kafka.producer_open("127.0.0.1", 19092, "producer-fault", 1000)
    if mode == "refused" {
        if problem.code != std.kafka.error_transport || problem.native_code != 111 { return 1 }
        println("Producer refusal: PASS"); return 0
    }
    if mode == "unsupported" {
        if problem.code != std.kafka.error_unsupported || p.connection.state != 0 { return 2 }
        println("Producer unsupported version: PASS"); return 0
    }
    if problem.code != 0 { println(problem.message); return 3 }
    if p.produce_version != 3 || p.connection.correlation_id != 2 { return 4 }
    records := std.kafka.message[]()
    records = append(records, std.kafka.message { key: std.kafka.bytes("k"), value: std.kafka.bytes("v"), timestamp_ms: 1 })
    // Local rejection must preserve stream and correlation.
    invalid, invalid_error := std.kafka.producer_publish_batch(p*, "bad/topic", 0, records, 1, 100)
    if invalid_error.code != std.kafka.error_invalid || p.connection.correlation_id != 2 || p.connection.state != 2 { return 5 }
    if mode == "valid" {
        large := "x"
        i := 0
        while i < 20 { large = large + large; i = i + 1 }
        large_cursor := std.kafka.new_cursor(large, 1048576)
        value := std.kafka.take(large_cursor*, 1048504)
        oversize := std.kafka.message[]()
        oversize = append(oversize, std.kafka.message { value: std.kafka.bytes(value) })
        rejected, rejected_error := std.kafka.producer_publish_batch(p*, "topic", 0, oversize, 1, 1000)
        if rejected_error.code != std.kafka.error_bounds || p.connection.correlation_id != 2 || p.connection.state != 2 { return 17 }
        sent, sent_error := std.kafka.producer_publish_batch(p*, "topic", 0, records, 0, 1000)
        if sent_error.code != 0 || sent.offset != -1 || p.connection.correlation_id != 3 { return 6 }
    }
    budget := 1000
    if mode == "timeout" { budget = 100 }
    start, start_error := std.time.monotonic_clock()
    result, publish_error := std.kafka.producer_publish_batch(p*, "topic", 0, records, 1, budget)
    end, end_error := std.time.monotonic_clock()
    if start_error.code != 0 || end_error.code != 0 { return 7 }
    if mode == "valid" {
        if publish_error.code != 0 || result.offset != 42 || p.connection.correlation_id != 4 { return 8 }
    } else if mode == "broker-error" {
        if publish_error.code != std.kafka.error_broker || publish_error.native_code != 6 || publish_error.fatal || p.connection.state != 2 { return 9 }
        again, again_error := std.kafka.producer_publish_batch(p*, "topic", 0, records, -1, 1000)
        if again_error.code != 0 || again.offset != 42 { return 10 }
    } else {
        if !publish_error.fatal || p.connection.state != 0 { return 11 }
        if mode == "malformed" && publish_error.code != std.kafka.error_protocol { return 12 }
        if mode == "timeout" {
            if publish_error.code != std.kafka.error_timeout || publish_error.native_code != 110 { return 13 }
            if end - start < 50000000 || end - start > 800000000 { return 14 }
        }
        if mode == "eof" && publish_error.code != std.kafka.error_transport { return 15 }
    }
    if std.kafka.producer_close(p*).code != 0 || std.kafka.producer_close(p*).code != 0 { return 16 }
    println("Producer fault " + mode + ": PASS")
    return 0
}
