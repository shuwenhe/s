package main

import "std.kafka"

func main() int {
    w := std.kafka.new_writer(1024)
    negative_one := -1
    minimum16 := -32768
    minimum32 := -2147483648
    minimum64 := -9223372036854775808
    std.kafka.put_int(w*, negative_one, 1)
    std.kafka.put_int(w*, minimum16, 2)
    std.kafka.put_int(w*, minimum32, 4)
    std.kafka.put_int(w*, minimum64, 8)
    std.kafka.put_int(w*, 9223372036854775807, 8)
    if w.failure.code != 0 {
        return 1
    }

    c := std.kafka.new_cursor(w.data, 1024)
    if std.kafka.read_int(c*, 1) != -1 || std.kafka.read_int(c*, 2) != -32768 ||
        std.kafka.read_int(c*, 4) != -2147483648 ||
        std.kafka.read_int(c*, 8) != -9223372036854775808 ||
        std.kafka.read_int(c*, 8) != 9223372036854775807 || std.kafka.finished(c*).code != 0 {
        return 2
    }

    values := []int { 0, 1, -1, 2147483647, -2147483648, 9223372036854775807, -9223372036854775808 }
    i := 0
    while i < len(values) {
        encoded := std.kafka.new_writer(64)
        value := values[i]
        std.kafka.put_varint(encoded*, value, 64)
        decoded := std.kafka.new_cursor(encoded.data, 64)
        if std.kafka.read_varint(decoded*, 64) != value || std.kafka.finished(decoded*).code != 0 {
            return 3
        }
        i = i + 1
    }

    invalid_data := std.kafka.byte_string(128) + std.kafka.byte_string(128) +
        std.kafka.byte_string(128) + std.kafka.byte_string(128) + std.kafka.byte_string(16)
    invalid := std.kafka.new_cursor(invalid_data, 64)
    std.kafka.read_uvarint(invalid*)
    if invalid.failure.code == 0 {
        return 4
    }
    check := remaining_checks()
    if check != 0 {
        return check
    }
    return record_checks()
}

func remaining_checks() int {
    w := std.kafka.new_writer(1024)
    empty := std.kafka.bytes("")
    null := std.kafka.nullable_bytes {}
    std.kafka.put_nullable(w*, empty, 4)
    std.kafka.put_nullable(w*, null, 4)
    std.kafka.put_compact(w*, empty)
    std.kafka.put_compact(w*, null)
    c := std.kafka.new_cursor(w.data, 1024)
    first := std.kafka.read_nullable(c*, 4, 1024)
    second := std.kafka.read_nullable(c*, 4, 1024)
    third := std.kafka.read_compact(c*, 1024)
    fourth := std.kafka.read_compact(c*, 1024)
    if !first.present || second.present || !third.present || fourth.present ||
        std.kafka.finished(c*).code != 0 {
        return 5
    }

    oversized := std.kafka.new_writer(2)
    std.kafka.put_string(oversized*, "long")
    if oversized.failure.code != std.kafka.error_bounds {
        return 6
    }
    truncated := std.kafka.new_cursor(std.kafka.byte_string(0), 1024)
    std.kafka.read_int(truncated*, 4)
    if truncated.failure.code != std.kafka.error_protocol {
        return 7
    }
    tags := std.kafka.new_writer(100)
    std.kafka.put_uvarint(tags*, 2)
    std.kafka.put_uvarint(tags*, 1)
    std.kafka.put_uvarint(tags*, 1)
    std.kafka.put_raw(tags*, "a")
    std.kafka.put_uvarint(tags*, 1)
    std.kafka.put_uvarint(tags*, 0)
    tagged := std.kafka.new_cursor(tags.data, 100)
    std.kafka.skip_tags(tagged*, 100)
    if tagged.failure.code != std.kafka.error_protocol {
        return 8
    }
    println("kafka protocol: PASS")
    return 0
}
