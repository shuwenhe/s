package main
import "std.kafka"

func main() int {
    // Literal bytes catch unsigned legacy decoders and incorrect byte order.
    request := std.kafka.broker_build_api_versions_request("s", 16909060)
    if len(request) != 11 { return 1 }
    expected := std.kafka.byte_string(0) + std.kafka.byte_string(18) +
        std.kafka.byte_string(0) + std.kafka.byte_string(0) +
        std.kafka.byte_string(1) + std.kafka.byte_string(2) +
        std.kafka.byte_string(3) + std.kafka.byte_string(4) +
        std.kafka.byte_string(0) + std.kafka.byte_string(1) + "s"
    if request != expected { return 2 }
    // A negative Kafka error is a broker error with its signed native code.
    negative := std.kafka.byte_string(255) + std.kafka.byte_string(255) +
        std.kafka.byte_string(0) + std.kafka.byte_string(0) +
        std.kafka.byte_string(0) + std.kafka.byte_string(0)
    none, problem := std.kafka.broker_parse_api_versions_response(negative)
    if problem.code != std.kafka.error_broker || problem.native_code != -1 { return 3 }
    zero := std.kafka.byte_string(0)
    body := zero + zero + zero + zero + zero + std.kafka.byte_string(1) +
        zero + std.kafka.byte_string(18) + zero + zero + zero + std.kafka.byte_string(4)
    versions, valid := std.kafka.broker_parse_api_versions_response(body)
    if valid.code != 0 || len(versions) != 1 { return 4 }
    if versions[0].api_key != 18 || versions[0].min_version != 0 || versions[0].max_version != 4 { return 5 }
    trailing, trailing_error := std.kafka.broker_parse_api_versions_response(body + zero)
    if trailing_error.code != std.kafka.error_protocol { return 6 }
    truncated, short_error := std.kafka.broker_parse_api_versions_response(zero)
    if short_error.code != std.kafka.error_protocol { return 7 }
    bad_count, count_error := std.kafka.broker_parse_api_versions_response(zero + zero + negative)
    if count_error.code == 0 { return 8 }
    missing, missing_error := std.kafka.broker_parse_api_versions_response(zero + zero + zero + zero + zero + std.kafka.byte_string(1))
    if missing_error.code != std.kafka.error_protocol { return 9 }
    // Min version -1 is invalid, even though the field is signed.
    invalid := zero + zero + zero + zero + zero + std.kafka.byte_string(1) +
        zero + std.kafka.byte_string(18) + std.kafka.byte_string(255) + std.kafka.byte_string(255) + zero + zero
    ranges, range_error := std.kafka.broker_parse_api_versions_response(invalid)
    if range_error.code != std.kafka.error_protocol { return 10 }
    // Signed int16/int32 exact extrema and a string containing an embedded NUL.
    w := std.kafka.new_writer(100)
    std.kafka.put_int(w*, -32768, 2)
    std.kafka.put_int(w*, -2147483648, 4)
    binary_text := "a" + zero + "b"
    std.kafka.put_string(w*, binary_text)
    c := std.kafka.new_cursor(w.data, 100)
    if std.kafka.read_int(c*, 2) != -32768 || std.kafka.read_int(c*, 4) != -2147483648 { return 11 }
    text := std.kafka.read_nullable(c*, 2, 100)
    if !text.present || text.data != "a" + zero + "b" || std.kafka.finished(c*).code != 0 { return 12 }
    closed := std.kafka.broker {}
    first_close := std.kafka.broker_close(closed*)
    second_close := std.kafka.broker_close(closed*)
    if first_close.code != 0 || second_close.code != 0 { return 13 }
    boundary_result := boundary_checks()
    if boundary_result != 0 { return boundary_result }
    println("kafka broker unit: PASS")
    return 0
}
