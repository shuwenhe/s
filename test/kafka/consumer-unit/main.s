package main
import ("std.kafka"; "std.tcp")
func main() int {
    records := std.kafka.message[]()
    headers := std.kafka.header[]()
    headers = append(headers, std.kafka.header { key: "h", value: std.kafka.bytes("x" + std.kafka.byte_string(0)) })
    headers = append(headers, std.kafka.header { key: "h" })
    records = append(records, std.kafka.message { key: std.kafka.bytes(""), value: std.kafka.bytes("a"), headers: headers, timestamp_ms: 100 })
    records = append(records, std.kafka.message { timestamp_ms: 99 })
    batch, encode_error := std.kafka.encode_record_batch(records)
    if encode_error.code != 0 { return 1 }
    // Broker assigns base offset=42 and partitionLeaderEpoch=7, outside CRC.
    head := std.kafka.new_writer(100)
    std.kafka.put_int(head*, 42, 8)
    std.kafka.put_int(head*, 7, 4)
    tail, slice_error := std.tcp.slice(batch, 12, len(batch))
    size := len(batch) - 12
    wire := std.kafka.new_writer(1048576)
    std.kafka.put_int(wire*, 42, 8)
    std.kafka.put_int(wire*, size, 4)
    std.kafka.put_int(wire*, 7, 4)
    rest, rest_error := std.tcp.slice(batch, 16, len(batch))
    std.kafka.put_raw(wire*, rest)
    decoded, problem := std.kafka.decode_record_batches(wire.data, 3, 42)
    if problem.code != 0 { println(problem.message); return 2 }
    if len(decoded.records) != 2 || decoded.next_offset != 44 { return 3 }
    a := decoded.records[0]
    b := decoded.records[1]
    if a.offset != 42 || a.partition != 3 || a.timestamp_ms != 100 || !a.key.present || a.key.data != "" || a.value.data != "a" { return 4 }
    if len(a.headers) != 2 || a.headers[0].value.data != "x" + std.kafka.byte_string(0) || a.headers[1].value.present { return 5 }
    if b.offset != 43 || b.timestamp_ms != 99 || b.key.present || b.value.present { return 6 }
    middle, middle_error := std.kafka.decode_record_batches(wire.data, 3, 43)
    if middle_error.code != 0 || len(middle.records) != 1 || middle.records[0].offset != 43 { return 7 }
    corrupted, corrupt_slice := std.tcp.slice(wire.data, 0, len(wire.data) - 1)
    bad, bad_error := std.kafka.decode_record_batches(corrupted + "X", 3, 42)
    if bad_error.code != std.kafka.error_protocol || len(bad.records) != 0 { return 8 }
    cut := 0
    while cut < len(wire.data) {
        prefix, prefix_error := std.tcp.slice(wire.data, 0, cut)
        invalid, invalid_error := std.kafka.decode_record_batches(prefix, 3, 42)
        if cut != 0 && invalid_error.code == 0 { return 9 }
        cut = cut + 1
    }
    println("Consumer broker offsets/timestamps/null/binary/headers/mid-batch/CRC/truncation: PASS")
    cases := decode_cases(wire.data)
    if cases != 0 { return cases }
    protocol := protocol_checks(wire.data)
    if protocol != 0 { return protocol }
    group := group_checks()
    if group != 0 { return group }
    group_wire := group_wire_checks()
    if group_wire != 0 { return group_wire }
    liveness := liveness_checks()
    if liveness != 0 { return liveness }
    offsets := offset_checks()
    if offsets != 0 { return offsets }
    description := describe_checks()
    if description != 0 { return description }
    reliability := reliability_checks()
    if reliability != 0 { return reliability }
    return transport_checks()
}
