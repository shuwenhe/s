package main
import ("std.kafka"; "std.time"; "std.prelude")
extern "intrinsic" func host_args() string[]
func main() int {
    args := host_args()
    if len(args) != 2 { return 99 }
    topic := args[1]
    p, problem := std.kafka.producer_open("127.0.0.1", 9092, "s-producer-benchmark", 10000)
    if problem.code != 0 { return 1 }
    now, clock_error := std.time.wall_clock()
    if clock_error.code != 0 { return 2 }
    payload := "x"
    i := 0
    while i < 8 { payload = payload + payload; i = i + 1 }
    record := std.kafka.message { value: std.kafka.bytes(payload), timestamp_ms: now / 1000000 }
    records := std.kafka.message[]()
    i = 0
    while i < 64 { records = append(records, record); i = i + 1 }
    serial_start, clock1 := std.time.monotonic_clock()
    size := 0
    i = 0
    while i < 50 {
        batch, encode_error := std.kafka.encode_record_batch(records)
        if encode_error.code != 0 { return 3 }
        size = len(batch)
        i = i + 1
    }
    serial_end, clock2 := std.time.monotonic_clock()
    single_start, clock3 := std.time.monotonic_clock()
    minimum := 9223372036854775807
    maximum := 0
    i = 0
    while i < 32 {
        start, clock4 := std.time.monotonic_clock()
        result, publish_error := std.kafka.producer_publish(p*, topic, 0, record, 1, 10000)
        end, clock5 := std.time.monotonic_clock()
        if publish_error.code != 0 || result.offset != i || clock4.code != 0 || clock5.code != 0 { return 4 }
        latency := end - start
        if latency < minimum { minimum = latency }
        if latency > maximum { maximum = latency }
        i = i + 1
    }
    single_end, clock6 := std.time.monotonic_clock()
    batch_start, clock7 := std.time.monotonic_clock()
    i = 0
    while i < 20 {
        result, publish_error := std.kafka.producer_publish_batch(p*, topic, 0, records, 1, 10000)
        if publish_error.code != 0 || result.offset != 32 + i * 64 { return 5 }
        i = i + 1
    }
    batch_end, clock8 := std.time.monotonic_clock()
    if clock1.code != 0 || clock2.code != 0 || clock3.code != 0 || clock6.code != 0 || clock7.code != 0 || clock8.code != 0 { return 6 }
    if std.kafka.producer_close(p*).code != 0 { return 7 }
    println("serialization_ns_per_64_records=" + std.prelude.to_string((serial_end - serial_start) / 50))
    println("encoded_batch_bytes=" + std.prelude.to_string(size))
    println("single_records_per_second=" + std.prelude.to_string(32000000000 / (single_end - single_start)))
    println("single_mean_latency_ns=" + std.prelude.to_string((single_end - single_start) / 32))
    println("single_min_latency_ns=" + std.prelude.to_string(minimum))
    println("single_max_latency_ns=" + std.prelude.to_string(maximum))
    println("batch_records_per_second=" + std.prelude.to_string(1280000000000 / (batch_end - batch_start)))
    println("benchmark offset checks: PASS")
    return 0
}
