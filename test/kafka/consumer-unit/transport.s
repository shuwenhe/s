package main
import "std.kafka"
func transport_checks() int {
    link := std.kafka.consumer_link {}
    request := std.kafka.broker_build_api_versions_request("test", 1)
    problem := std.kafka.consumer_exchange_begin(link*, request, 1000)
    if problem.code != std.kafka.error_closed { return 20 }
    link.connection = std.kafka.broker { state: 2, correlation_id: 1, client_id: "test" }
    bad := std.kafka.consumer_exchange_begin(link*, "bad", 1000)
    if bad.code != std.kafka.error_bounds || link.connection.correlation_id != 1 { return 21 }
    started := std.kafka.consumer_exchange_begin(link*, request, 1000)
    if started.code != 0 || link.state != 1 || link.connection.correlation_id != 1 { return 22 }
    again := std.kafka.consumer_exchange_begin(link*, request, 1000)
    if again.code != std.kafka.error_invalid { return 23 }
    fragments := std.kafka.consumer_link {}
    expected := ""
    i := 0
    while i < 33 {
        part := std.kafka.byte_string(i) + "fragment"
        std.kafka._kc_body_append(fragments*, part)
        expected = expected + part
        i = i + 1
    }
    assembled := std.kafka._kc_body_collect(fragments.body_fragments)
    if assembled != expected || fragments.body_received != len(expected) || len(fragments.body_fragments) > 6 { return 24 }
    println("Consumer exchange caller validation/pending/correlation: PASS")
    return 0
}
