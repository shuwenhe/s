package main
import ("std.kafka"; "std.time")
extern "intrinsic" func host_args() string[]
func exchange(std.kafka.consumer_link* link, string request) int {
    issue := std.kafka.consumer_exchange_begin(link*, request, 10000)
    if issue.code != 0 { return issue.code }
    while link.state != 4 && link.problem.code == 0 { std.kafka.consumer_exchange_step(link*, 1) }
    return link.problem.code
}
func main() int {
    args := host_args()
    if len(args) != 2 { return 99 }
    topic := args[1]
    link, problem := std.kafka.consumer_link_open("127.0.0.1", 9092, "s-consumer-phase1", 5000)
    if problem.code != 0 { println(problem.message); return 1 }
    if !std.kafka.consumer_supports(link.versions, 3, 4) || !std.kafka.consumer_supports(link.versions, 1, 4) { return 2 }
    topics := string[] { topic }
    metadata_request, metadata_error := std.kafka.consumer_build_metadata("s-consumer-phase1", link.connection.correlation_id, topics)
    if metadata_error.code != 0 || exchange(link*, metadata_request) != 0 { return 3 }
    meta, parse_error := std.kafka.consumer_parse_metadata(link.body)
    if parse_error.code != 0 || len(meta.partitions) != 2 || len(meta.brokers) != 2 { return 4 }
    p, producer_error := std.kafka.producer_open("127.0.0.1", 9092, "native-phase1-producer", 5000)
    if producer_error.code != 0 { return 5 }
    now, clock_error := std.time.wall_clock()
    if clock_error.code != 0 { return 6 }
    timestamp := now / 1000000
    zero := std.kafka.byte_string(0)
    headers := std.kafka.header[]()
    headers = append(headers, std.kafka.header { key: "h", value: std.kafka.bytes("x" + zero) })
    headers = append(headers, std.kafka.header { key: "h" })
    headers = append(headers, std.kafka.header { key: "empty", value: std.kafka.bytes("") })
    records := std.kafka.message[]()
    records = append(records, std.kafka.message { key: std.kafka.bytes("k" + zero), value: std.kafka.bytes("v" + zero), headers: headers, timestamp_ms: timestamp })
    records = append(records, std.kafka.message { timestamp_ms: timestamp - 1 })
    records = append(records, std.kafka.message { key: std.kafka.bytes(""), value: std.kafka.bytes(""), timestamp_ms: timestamp + 1 })
    partition_id := 0
    while partition_id < 2 {
        produced, produce_error := std.kafka.producer_publish_batch(p*, topic, partition_id, records, -1, 5000)
        if produce_error.code != 0 || produced.offset != 0 { return 7 }
        request, request_error := std.kafka.consumer_build_fetch("s-consumer-phase1", link.connection.correlation_id, topic, partition_id, 0, 100, 786432)
        if request_error.code != 0 || exchange(link*, request) != 0 { return 8 }
        fetched, fetch_error := std.kafka.consumer_parse_fetch(link.body, topic, partition_id)
        if fetch_error.code != 0 { println(fetch_error.message); return 9 }
        decoded, decode_error := std.kafka.decode_record_batches(fetched.data, partition_id, 0)
        if decode_error.code != 0 || len(decoded.records) != 3 || decoded.next_offset != 3 { println(decode_error.message); return 10 }
        a := decoded.records[0]
        b := decoded.records[1]
        c := decoded.records[2]
        if a.offset != 0 || a.partition != partition_id || a.timestamp_ms != timestamp || a.key.data != "k" + zero || a.value.data != "v" + zero { return 11 }
        if len(a.headers) != 3 || a.headers[0].value.data != "x" + zero || a.headers[1].value.present || !a.headers[2].value.present || a.headers[2].value.data != "" { return 12 }
        if b.offset != 1 || b.timestamp_ms != timestamp - 1 || b.key.present || b.value.present { return 13 }
        if c.offset != 2 || c.timestamp_ms != timestamp + 1 || !c.key.present || !c.value.present || c.key.data != "" || c.value.data != "" { return 14 }
        partition_id = partition_id + 1
    }
    if std.kafka.producer_close(p*).code != 0 || std.kafka.consumer_link_close(link*).code != 0 { return 15 }
    println("Consumer Phase 1 REAL Kafka 3.9.1 Metadata/Fetch/native Producer/exact fields/two partitions: PASS")
    return 0
}
