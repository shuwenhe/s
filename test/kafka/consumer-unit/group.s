package main
import "std.kafka"
func group_checks() int {
    topics := string[] { "topic" }
    payload, payload_error := std.kafka.consumer_subscription(topics)
    if payload_error.code != 0 { return 50 }
    parsed, parsed_error := std.kafka.consumer_parse_subscription(payload)
    if parsed_error.code != 0 || len(parsed) != 1 || parsed[0] != "topic" { return 51 }
    members := std.kafka.consumer_member[]()
    members = append(members, std.kafka.consumer_member { member_id: "b", topics: topics })
    members = append(members, std.kafka.consumer_member { member_id: "a", topics: topics })
    meta := std.kafka.consumer_metadata { topics: topics }
    meta.partitions = append(meta.partitions, std.kafka.topic_partition { topic: "topic", partition_id: 1, leader_id: 1 })
    meta.partitions = append(meta.partitions, std.kafka.topic_partition { topic: "topic", partition_id: 0, leader_id: 1 })
    assigned, assign_error := std.kafka.consumer_range_assign(members, meta)
    if assign_error.code != 0 || len(assigned) != 2 { return 52 }
    if assigned[0].member_id != "a" || assigned[0].partitions[0].partition_id != 0 || assigned[1].partitions[0].partition_id != 1 { return 53 }
    encoded, encoded_error := std.kafka.consumer_assignment_encode(assigned[0].partitions)
    decoded, decoded_error := std.kafka.consumer_assignment_parse(encoded)
    if encoded_error.code != 0 || decoded_error.code != 0 || len(decoded) != 1 || decoded[0].topic != "topic" { return 54 }
    members = append(members, std.kafka.consumer_member { member_id: "c", topics: topics })
    three, three_error := std.kafka.consumer_range_assign(members, meta)
    if three_error.code != 0 || len(three[2].partitions) != 0 { return 55 }
    members = append(members, std.kafka.consumer_member { member_id: "a", topics: topics })
    duplicate, duplicate_error := std.kafka.consumer_range_assign(members, meta)
    if duplicate_error.code != std.kafka.error_protocol { return 56 }
    println("Consumer subscription/assignment v0 / deterministic Range / empty member / duplicate rejection: PASS")
    return 0
}
