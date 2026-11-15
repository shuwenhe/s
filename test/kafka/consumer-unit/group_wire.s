package main
import "std.kafka"
func group_wire_checks() int {
    topics := string[] { "topic" }
    request, problem := std.kafka.consumer_build_join("client", 1, "group", "", topics, 10000, 15000)
    if problem.code != 0 { return 60 }
    c := std.kafka.new_cursor(request, 1048576)
    if std.kafka.read_int(c*, 2) != 11 || std.kafka.read_int(c*, 2) != 2 || std.kafka.read_int(c*, 4) != 1 { return 61 }
    client := std.kafka.read_string(c*, 32767)
    group := std.kafka.read_string(c*, 255)
    session := std.kafka.read_int(c*, 4)
    rebalance := std.kafka.read_int(c*, 4)
    member := std.kafka.read_string(c*, 32767)
    protocol := std.kafka.read_string(c*, 32767)
    if client != "client" || group != "group" || session != 10000 || rebalance != 15000 || member != "" || protocol != "consumer" { return 62 }
    if std.kafka.read_int(c*, 4) != 1 || std.kafka.read_string(c*, 32767) != "range" { return 63 }
    subscription := std.kafka.read_nullable(c*, 4, 1048576)
    if !subscription.present || std.kafka.finished(c*).code != 0 { return 64 }
    w := std.kafka.new_writer(1024)
    std.kafka.put_int(w*, 0, 4)
    std.kafka.put_int(w*, 0, 2)
    std.kafka.put_int(w*, 7, 4)
    std.kafka.put_string(w*, "range")
    std.kafka.put_string(w*, "a")
    std.kafka.put_string(w*, "a")
    std.kafka.put_int(w*, 1, 4)
    std.kafka.put_string(w*, "a")
    std.kafka.put_nullable(w*, subscription, 4)
    joined, join_error := std.kafka.consumer_parse_join(w.data)
    if join_error.code != 0 || joined.generation_id != 7 || joined.member_id != "a" || len(joined.members) != 1 { return 65 }
    truncated, short_error := std.kafka.consumer_parse_join("x")
    if short_error.code != std.kafka.error_protocol { return 66 }
    println("Consumer JoinGroup v2 fixed fields and response: PASS")
    return 0
}
