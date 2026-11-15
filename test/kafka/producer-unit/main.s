package main
import ("std.kafka"; "std.tcp")

func main() int {
    if std.kafka.crc32c("123456789") != 3808858755 { return 1 }
    records := std.kafka.message[]()
    records = append(records, std.kafka.message { value: std.kafka.bytes("hello"), timestamp_ms: 1700000000000 })
    batch, problem := std.kafka.encode_record_batch(records)
    if problem.code != 0 { println(problem.message); return 2 }
    // Independent golden fixture generated from Kafka's documented batch layout.
    expected := golden_batch()
    if batch != expected { println("golden batch mismatch"); return 3 }
    valid := std.kafka.validate_record_batch(batch)
    if valid.code != 0 { println(valid.message); return 4 }
    prefix, slice_error := std.tcp.slice(batch, 0, len(batch) - 1)
    broken := std.kafka.validate_record_batch(prefix + "X")
    if broken.code != std.kafka.error_protocol { return 5 }
    short := std.kafka.validate_record_batch(prefix)
    if short.code == 0 { return 6 }
    empty, empty_error := std.kafka.encode_record_batch(std.kafka.message[]())
    if empty_error.code != std.kafka.error_invalid { return 7 }
    h := std.kafka.header[]()
    h = append(h, std.kafka.header { key: "h", value: std.kafka.bytes("a" + std.kafka.byte_string(0) + "b") })
    h = append(h, std.kafka.header { key: "h", value: std.kafka.nullable_bytes {} })
    records = append(records, std.kafka.message { key: std.kafka.bytes(""), headers: h, timestamp_ms: 1699999999999 })
    batch2, error2 := std.kafka.encode_record_batch(records)
    if error2.code != 0 || std.kafka.validate_record_batch(batch2).code != 0 { return 8 }
    records = append(records, std.kafka.message { timestamp_ms: -1 })
    bad, bad_error := std.kafka.encode_record_batch(records)
    if bad_error.code != std.kafka.error_invalid { return 9 }
    large := "x"
    i := 0
    while i < 20 { large = large + large; i = i + 1 }
    huge := std.kafka.message[]()
    huge = append(huge, std.kafka.message { value: std.kafka.bytes(large) })
    huge_batch, huge_error := std.kafka.encode_record_batch(huge)
    if huge_error.code != std.kafka.error_bounds { return 10 }
    println("Kafka producer batch golden/CRC/bounds/null/binary/headers: PASS")
    malformed := malformed_checks()
    if malformed != 0 { return malformed }
    limits := limit_checks()
    if limits != 0 { return limits }
    return produce_checks()
}
