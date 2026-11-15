package main
import "std.kafka"
func produce_checks() int {
    records := std.kafka.message[]()
    records = append(records, std.kafka.message { value: std.kafka.bytes("hello"), timestamp_ms: 1700000000000 })
    request, problem := std.kafka.build_produce_request("s", 7, "topic", 2, records, -1, 5000)
    if problem.code != 0 { return 20 }
    c := std.kafka.new_cursor(request, 1048576)
    if std.kafka.read_int(c*, 2) != 0 || std.kafka.read_int(c*, 2) != 3 || std.kafka.read_int(c*, 4) != 7 { return 21 }
    if std.kafka.read_string(c*, 32767) != "s" { return 22 }
    transaction := std.kafka.read_nullable(c*, 2, 100)
    if transaction.present || std.kafka.read_int(c*, 2) != -1 || std.kafka.read_int(c*, 4) != 5000 { return 23 }
    if std.kafka.read_int(c*, 4) != 1 || std.kafka.read_string(c*, 32767) != "topic" { return 24 }
    if std.kafka.read_int(c*, 4) != 1 || std.kafka.read_int(c*, 4) != 2 { return 25 }
    batch := std.kafka.read_nullable(c*, 4, 1048576)
    if !batch.present || batch.data != golden_batch() || std.kafka.finished(c*).code != 0 { return 26 }
    i := 0
    while i < 3 {
        acks := i - 1
        req, err := std.kafka.build_produce_request("s", 1, "topic", 0, records, acks, 100)
        if err.code != 0 { return 27 }
        i = i + 1
    }
    invalid, invalid_error := std.kafka.build_produce_request("s", 1, "bad/topic", 0, records, 1, 100)
    if invalid_error.code != std.kafka.error_invalid { return 28 }
    invalid2, invalid_error2 := std.kafka.build_produce_request("s", 1, "topic", -1, records, 1, 100)
    if invalid_error2.code != std.kafka.error_invalid { return 29 }
    invalid3, invalid_error3 := std.kafka.build_produce_request("s", 1, "topic", 0, records, 2, 100)
    if invalid_error3.code != std.kafka.error_invalid { return 30 }
    response := response_body(0)
    result, response_error := std.kafka.parse_produce_response(response, "topic", 2)
    if response_error.code != 0 || result.partition != 2 || result.offset != 42 || result.timestamp_ms != -1 { return 31 }
    failed, broker_error := std.kafka.parse_produce_response(response_body(6), "topic", 2)
    if broker_error.code != std.kafka.error_broker || broker_error.native_code != 6 || broker_error.fatal { return 32 }
    wrong, wrong_error := std.kafka.parse_produce_response(response, "other", 2)
    if wrong_error.code != std.kafka.error_protocol { return 33 }
    wrong2, wrong_error2 := std.kafka.parse_produce_response(response, "topic", 3)
    if wrong_error2.code != std.kafka.error_protocol { return 34 }
    trailing, trailing_error := std.kafka.parse_produce_response(response + "X", "topic", 2)
    if trailing_error.code != std.kafka.error_protocol { return 35 }
    cut := 0
    while cut < len(response) {
        short := std.kafka.new_cursor(response, 1048576)
        prefix := std.kafka.take(short*, cut)
        missing, missing_error := std.kafka.parse_produce_response(prefix, "topic", 2)
        if missing_error.code == 0 { return 36 }
        cut = cut + 1
    }
    closed := std.kafka.producer {}
    result2, closed_error := std.kafka.producer_publish_batch(closed*, "topic", 0, records, 1, 100)
    if closed_error.code != std.kafka.error_closed { return 37 }
    if std.kafka.producer_close(closed*).code != 0 { return 38 }
    println("Kafka Produce v3 schema/ACK/input/response/errors: PASS")
    return 0
}
func response_body(int status) string {
    w := std.kafka.new_writer(100)
    std.kafka.put_int(w*, 1, 4)
    std.kafka.put_string(w*, "topic")
    std.kafka.put_int(w*, 1, 4)
    std.kafka.put_int(w*, 2, 4)
    std.kafka.put_int(w*, status, 2)
    std.kafka.put_int(w*, 42, 8)
    std.kafka.put_int(w*, -1, 8)
    std.kafka.put_int(w*, 0, 4)
    return w.data
}
