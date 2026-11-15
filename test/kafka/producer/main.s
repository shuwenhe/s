package main
import ("std.kafka"; "std.time"; "std.prelude")
extern "intrinsic" func host_args() string[]
func check(std.kafka.producer* p, string topic, int partition_id, std.kafka.message record, int acks, int expected) int {
    result, problem := std.kafka.producer_publish(p*, topic, partition_id, record, acks, 10000)
    if problem.code != 0 { return 1 }
    if result.offset != expected || result.partition != partition_id { return 2 }
    return 0
}
func main() int {
    args := host_args()
    if len(args) != 2 { return 99 }
    topic := args[1]
    p, problem := std.kafka.producer_open("127.0.0.1", 9092, "s-producer-real", 10000)
    if problem.code != 0 { println(problem.message); return 1 }
    if p.produce_version != 3 { return 2 }
    now, clock_error := std.time.wall_clock()
    if clock_error.code != 0 { return 3 }
    timestamp := now / 1000000
    record := std.kafka.message { value: std.kafka.bytes("hello"), timestamp_ms: timestamp }
    if check(p*, topic, 0, record, 1, 0) != 0 { return 4 }
    zero := std.kafka.byte_string(0)
    headers := std.kafka.header[]()
    headers = append(headers, std.kafka.header { key: "tag", value: std.kafka.bytes("a" + zero + "b") })
    headers = append(headers, std.kafka.header { key: "tag", value: std.kafka.nullable_bytes {} })
    headers = append(headers, std.kafka.header { key: "empty", value: std.kafka.bytes("") })
    record = std.kafka.message { key: std.kafka.bytes("k" + zero), value: std.kafka.bytes("v" + zero + "x"), headers: headers, timestamp_ms: timestamp }
    if check(p*, topic, 0, record, -1, 1) != 0 { return 5 }
    record = std.kafka.message { key: std.kafka.bytes("tombstone"), timestamp_ms: timestamp }
    if check(p*, topic, 0, record, -1, 2) != 0 { return 6 }
    record = std.kafka.message { key: std.kafka.bytes(""), value: std.kafka.bytes(""), timestamp_ms: timestamp }
    if check(p*, topic, 0, record, 1, 3) != 0 { return 7 }
    records := std.kafka.message[]()
    records = append(records, std.kafka.message { value: std.kafka.bytes("batch-0"), timestamp_ms: timestamp })
    records = append(records, std.kafka.message { key: std.kafka.bytes("batch-key"), value: std.kafka.bytes("batch-1"), timestamp_ms: timestamp - 1 })
    records = append(records, std.kafka.message { value: std.kafka.bytes("batch-2"), timestamp_ms: timestamp + 1 })
    batch_result, batch_error := std.kafka.producer_publish_batch(p*, topic, 0, records, -1, 10000)
    if batch_error.code != 0 || batch_result.offset != 4 { println(batch_error.message); return 8 }
    record = std.kafka.message { value: std.kafka.bytes("ack-zero"), timestamp_ms: timestamp }
    if check(p*, topic, 0, record, 0, -1) != 0 { return 9 }
    record = std.kafka.message { value: std.kafka.bytes("ack-barrier"), timestamp_ms: timestamp }
    if check(p*, topic, 0, record, 1, 8) != 0 { return 10 }
    large := "L"
    i := 0
    while i < 19 { large = large + large; i = i + 1 }
    record = std.kafka.message { key: std.kafka.bytes("large"), value: std.kafka.bytes(large), timestamp_ms: timestamp }
    if check(p*, topic, 0, record, -1, 9) != 0 { return 11 }
    record = std.kafka.message { value: std.kafka.bytes("partition-one"), timestamp_ms: timestamp }
    if check(p*, topic, 1, record, 1, 0) != 0 { return 12 }
    invalid, invalid_error := std.kafka.producer_publish(p*, "bad/topic", 0, record, 1, 1000)
    if invalid_error.code != std.kafka.error_invalid { return 13 }
    missing, missing_error := std.kafka.producer_publish(p*, topic + "-missing", 0, record, 1, 10000)
    if missing_error.code != std.kafka.error_broker || missing_error.native_code != 3 { println(missing_error.message); println(std.prelude.to_string(missing_error.native_code)); return 14 }
    wrong, wrong_error := std.kafka.producer_open("127.0.0.1", 19093, "s-wrong-leader", 10000)
    if wrong_error.code != 0 { return 15 }
    rejected, rejected_error := std.kafka.producer_publish(wrong*, topic, 0, record, 1, 10000)
    if rejected_error.code != std.kafka.error_broker || rejected_error.native_code != 6 { return 16 }
    if std.kafka.producer_close(wrong*).code != 0 { return 17 }
    if std.kafka.producer_close(p*).code != 0 { return 18 }
    println("Real Kafka Produce v3 / RecordBatch v2 / ACK -1,0,1 / keys / headers / batches / 512KiB / partitions / broker errors: PASS")
    return 0
}
