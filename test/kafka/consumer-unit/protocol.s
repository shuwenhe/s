package main
import "std.kafka"
func protocol_checks(string batch) int {
    topics := string[] { "topic" }
    request, request_error := std.kafka.consumer_build_metadata("test", 9, topics)
    if request_error.code != 0 { return 30 }
    q := std.kafka.new_cursor(request, 1048576)
    if std.kafka.read_int(q*, 2) != 3 || std.kafka.read_int(q*, 2) != 4 || std.kafka.read_int(q*, 4) != 9 { return 31 }
    client := std.kafka.read_string(q*, 32767)
    count := std.kafka.read_int(q*, 4)
    topic := std.kafka.read_string(q*, 249)
    if client != "test" || count != 1 || topic != "topic" || std.kafka.read_int(q*, 1) != 0 || std.kafka.finished(q*).code != 0 { return 32 }
    w := std.kafka.new_writer(1024)
    std.kafka.put_int(w*, 0, 4)
    std.kafka.put_int(w*, 1, 4)
    std.kafka.put_int(w*, 1, 4)
    std.kafka.put_string(w*, "127.0.0.1")
    std.kafka.put_int(w*, 9092, 4)
    std.kafka.put_int(w*, -1, 2)
    std.kafka.put_int(w*, -1, 2)
    std.kafka.put_int(w*, 1, 4)
    std.kafka.put_int(w*, 1, 4)
    std.kafka.put_int(w*, 0, 2)
    std.kafka.put_string(w*, "topic")
    std.kafka.put_int(w*, 0, 1)
    std.kafka.put_int(w*, 1, 4)
    std.kafka.put_int(w*, 0, 2)
    std.kafka.put_int(w*, 3, 4)
    std.kafka.put_int(w*, 1, 4)
    std.kafka.put_int(w*, 1, 4)
    std.kafka.put_int(w*, 1, 4)
    std.kafka.put_int(w*, 1, 4)
    std.kafka.put_int(w*, 1, 4)
    meta, meta_error := std.kafka.consumer_parse_metadata(w.data)
    if meta_error.code != 0 || len(meta.brokers) != 1 || len(meta.partitions) != 1 || meta.partitions[0].partition_id != 3 { return 33 }
    endpoint, endpoint_error := std.kafka.consumer_metadata_endpoint(meta, 1)
    if endpoint_error.code != 0 || endpoint.host != "127.0.0.1" || endpoint.port != 9092 { return 34 }
    f := std.kafka.new_writer(1048576)
    std.kafka.put_int(f*, 0, 4)
    std.kafka.put_int(f*, 1, 4)
    std.kafka.put_string(f*, "topic")
    std.kafka.put_int(f*, 1, 4)
    std.kafka.put_int(f*, 3, 4)
    std.kafka.put_int(f*, 0, 2)
    std.kafka.put_int(f*, 44, 8)
    std.kafka.put_int(f*, 44, 8)
    std.kafka.put_int(f*, -1, 4)
    size := len(batch)
    std.kafka.put_int(f*, size, 4)
    std.kafka.put_raw(f*, batch)
    fetched, fetch_error := std.kafka.consumer_parse_fetch(f.data, "topic", 3)
    if fetch_error.code != 0 || fetched.data != batch || fetched.high_watermark != 44 { return 35 }
    wrong, wrong_error := std.kafka.consumer_parse_fetch(f.data, "wrong", 3)
    if wrong_error.code != std.kafka.error_protocol { return 36 }
    println("Consumer Metadata v4 / Fetch v4 fixed schema and identity: PASS")
    return 0
}
