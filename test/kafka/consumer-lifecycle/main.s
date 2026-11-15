package main
import "std.kafka"
func owned_link() std.kafka.consumer_link {
    fragments := string[] { "fragment" }
    return std.kafka.consumer_link { outgoing: "pending-write", body: "fetch-response", size_header: "head", body_fragments: fragments, state: 3, response_size: 20, body_received: 5 }
}
func cleared(std.kafka.consumer_link link) bool {
    return len(link.outgoing) == 0 && len(link.body) == 0 && len(link.body_fragments) == 0 && len(link.size_header) == 0 && link.state == 0 && link.connection.state != 2
}
func main() int {
    endpoints := std.kafka.endpoint[]()
    endpoints = append(endpoints, std.kafka.endpoint { host: "invalid-ipv4", port: 1 })
    i := 0
    while i < 2 {
        c, issue := std.kafka.consumer_new(std.kafka.consumer_config { bootstrap: endpoints, group_id: "cleanup" })
        if issue.code != 0 { return 1 }
        c.state = 6
        c.member_id = "unavailable-member"
        c.bootstrap_link = owned_link()
        c.group_link = owned_link()
        c.fetch_link = owned_link()
        c.heartbeat_link = owned_link()
        c.decoder = std.kafka.consumer_decoder_new("partial-decoder", 0, 0, false)
        c.decoder.output.records = append(c.decoder.output.records, std.kafka.message { value: std.kafka.bytes("decoded") })
        c.commit_snapshot = append(c.commit_snapshot, std.kafka.topic_partition { topic: "t", partition_id: 0 })
        c.assigned = c.commit_snapshot
        c.queue = c.decoder.output.records
        c.outstanding_delivery_id = 7
        timeout := 10
        if i == 0 { timeout = 0 }
        problem := std.kafka.consumer_close(c*, timeout)
        if problem.code == 0 { return 2 }
        if !c.closed || !cleared(c.bootstrap_link) || !cleared(c.group_link) || !cleared(c.fetch_link) || !cleared(c.heartbeat_link) { return 3 }
        if len(c.decoder.input.data) != 0 || len(c.decoder.output.records) != 0 || len(c.commit_snapshot) != 0 || len(c.queue) != 0 || len(c.assigned) != 0 || c.outstanding_delivery_id != 0 { return 4 }
        if std.kafka.consumer_close(c*, 10).code != 0 { return 5 }
        i = i + 1
    }
    println("All role buffers and pending decode/commit/delivery cleanup after failed close: PASS")
    return 0
}
