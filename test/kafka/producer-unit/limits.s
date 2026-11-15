package main
import ("std.kafka"; "std.tcp")
func limit_checks() int {
    records := std.kafka.message[]()
    i := 0
    while i < 4096 { records = append(records, std.kafka.message {}); i = i + 1 }
    batch, problem := std.kafka.encode_record_batch(records)
    if problem.code != 0 || std.kafka.validate_record_batch(batch).code != 0 { return 50 }
    records = append(records, std.kafka.message {})
    too_many, count_error := std.kafka.encode_record_batch(records)
    if count_error.code != std.kafka.error_invalid { return 51 }
    headers := std.kafka.header[]()
    i = 0
    while i < 4096 { headers = append(headers, std.kafka.header { key: "h" }); i = i + 1 }
    one := std.kafka.message[]()
    one = append(one, std.kafka.message { headers: headers })
    with_headers, header_error := std.kafka.encode_record_batch(one)
    if header_error.code != 0 || std.kafka.validate_record_batch(with_headers).code != 0 { return 52 }
    headers = append(headers, std.kafka.header { key: "h" })
    many_headers := std.kafka.message[]()
    many_headers = append(many_headers, std.kafka.message { headers: headers })
    rejected, rejected_error := std.kafka.encode_record_batch(many_headers)
    if rejected_error.code != std.kafka.error_bounds { return 53 }
    large := "x"
    i = 0
    while i < 20 { large = large + large; i = i + 1 }
    value, slice_error := std.tcp.slice(large, 0, 1048504)
    boundary := std.kafka.message[]()
    boundary = append(boundary, std.kafka.message { value: std.kafka.bytes(value) })
    exact, exact_error := std.kafka.encode_record_batch(boundary)
    if exact_error.code != 0 || len(exact) != 1048576 || std.kafka.validate_record_batch(exact).code != 0 { return 54 }
    request, request_error := std.kafka.build_produce_request("", 1, "t", 0, boundary, 1, 1000)
    if request_error.code != std.kafka.error_bounds || request != "" { return 55 }
    invalid, invalid_error := std.kafka.build_produce_request("", 1, "..", 0, one, 1, 1000)
    if invalid_error.code != std.kafka.error_invalid { return 56 }
    println("Kafka exact record/header/batch/frame limits: PASS")
    return 0
}
