package main

import "std.kafka"

func record_checks() int {
    if std.kafka.crc32c("123456789") != 3808858755 {
        return 20
    }
    headers := []std.kafka.header {
        { key: "same", value: std.kafka.nullable_bytes {} },
        { key: "same", value: std.kafka.bytes("") }
    }
    records := []std.kafka.message {
        { value: std.kafka.bytes("a\x00\xff"), headers: headers, timestamp_ms: 100 },
        { key: std.kafka.bytes(""), timestamp_ms: 90 }
    }
    data, err := std.kafka.encode_batch(records, 4096)
    if err.code != 0 {
        return 21
    }
    result, decode_err := std.kafka.decode_batches(data, 0, 20, 4096)
    if decode_err.code != 0 || result.count != 2 || result.next_offset != 2 ||
        result.records[0].value.data != "a\x00\xff" || result.records[0].key.present ||
        !result.records[1].key.present || result.records[1].value.present ||
        result.records[1].timestamp_ms != 90 || len(result.records[0].headers) != 2 ||
        result.records[0].headers[0].value.present || !result.records[0].headers[1].value.present {
        return 22
    }
    seek, seek_err := std.kafka.decode_batches(data, 1, 20, 4096)
    if seek_err.code != 0 || seek.count != 1 || seek.records[0].offset != 1 || seek.next_offset != 2 {
        return 23
    }
    limited, limited_err := std.kafka.decode_batches(data, 0, 1, 4096)
    if limited_err.code != 0 || limited.count != 1 || limited.next_offset != 1 {
        return 24
    }
    empty, empty_err := std.kafka.decode_batches("", 7, 20, 4096)
    if empty_err.code != 0 || empty.count != 0 || empty.next_offset != 7 {
        return 25
    }
    broken, broken_err := std.kafka.decode_batches("\x00", 0, 20, 4096)
    if broken_err.code == 0 || broken.next_offset != 0 {
        return 26
    }
    return 0
}
