package main
import "std.kafka"
func describe_checks() int {
    request, issue := std.kafka.consumer_build_describe("client", 1, "group")
    if issue.code != 0 { return 100 }
    w := std.kafka.new_writer(1024)
    std.kafka.put_int(w*, 0, 4)
    std.kafka.put_int(w*, 1, 4)
    std.kafka.put_int(w*, 0, 2)
    std.kafka.put_string(w*, "group")
    std.kafka.put_string(w*, "Stable")
    std.kafka.put_string(w*, "consumer")
    std.kafka.put_string(w*, "range")
    std.kafka.put_int(w*, 0, 4)
    description, problem := std.kafka.consumer_parse_describe(w.data, "group")
    if problem.code != 0 || description.state != "Stable" || description.protocol_name != "range" || description.member_count != 0 { return 101 }
    wrong, wrong_error := std.kafka.consumer_parse_describe(w.data, "other")
    if wrong_error.code != std.kafka.error_protocol { return 102 }
    println("Consumer DescribeGroups v1 identity/schema: PASS")
    return 0
}
