package main
import "std.kafka"
func boundary_checks() int {
    zero := std.kafka.byte_string(0)
    ff := std.kafka.byte_string(255)
    w := std.kafka.new_writer(20)
    std.kafka.put_int(w*, -32768, 2)
    std.kafka.put_int(w*, -2147483648, 4)
    if w.data != std.kafka.byte_string(128) + zero + std.kafka.byte_string(128) + zero + zero + zero { return 20 }
    c := std.kafka.new_cursor(ff + ff + ff + ff + ff + ff, 6)
    if std.kafka.read_int(c*, 2) != -1 || std.kafka.read_int(c*, 4) != -1 { return 21 }
    invalid_count := zero + zero + ff + ff + ff + ff
    a, ea := std.kafka.broker_parse_api_versions_response(invalid_count)
    if ea.code != std.kafka.error_protocol { return 22 }
    huge_count := zero + zero + zero + zero + std.kafka.byte_string(16) + std.kafka.byte_string(1)
    b, eb := std.kafka.broker_parse_api_versions_response(huge_count)
    if eb.code != std.kafka.error_protocol { return 23 }
    entry := zero + std.kafka.byte_string(18) + zero + zero + zero + std.kafka.byte_string(4)
    duplicate := zero + zero + zero + zero + zero + std.kafka.byte_string(2) + entry + entry
    d, ed := std.kafka.broker_parse_api_versions_response(duplicate)
    if ed.code != std.kafka.error_protocol { return 24 }
    reversed := zero + zero + zero + zero + zero + std.kafka.byte_string(1) +
        zero + std.kafka.byte_string(18) + zero + std.kafka.byte_string(4) + zero + std.kafka.byte_string(3)
    r, er := std.kafka.broker_parse_api_versions_response(reversed)
    if er.code != std.kafka.error_protocol { return 25 }
    text := "x"
    i := 0
    while i < 15 { text = text + text; i = i + 1 }
    if std.kafka.broker_build_api_versions_request(text, 1) != "" { return 26 }
    if std.kafka.broker_build_api_versions_request("s", -1) != "" { return 27 }
    bad_string := std.kafka.new_cursor(ff + ff, 2)
    field := std.kafka.read_nullable(bad_string*, 2, 100)
    if field.present { return 28 }
    unterminated := std.kafka.new_cursor(zero + std.kafka.byte_string(3) + "a", 100)
    missing := std.kafka.read_nullable(unterminated*, 2, 100)
    if unterminated.failure.code != std.kafka.error_protocol { return 29 }
    closed := std.kafka.broker {}
    body, problem := std.kafka.broker_send_request(closed*, "", 100)
    if problem.code != std.kafka.error_closed { return 30 }
    invalid, connect_error := std.kafka.broker_connect("127.0.0.1", 9092, "s", 0)
    if connect_error.code != std.kafka.error_invalid || invalid.state != 0 { return 31 }
    return 0
}
