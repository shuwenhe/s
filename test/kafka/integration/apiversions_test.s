// Real Kafka 3.9.1 acceptance: no peer fixtures and no skip-on-connect-failure.
func apiversions_checks() int {
    b, problem := std.kafka.broker_connect("127.0.0.1", 9092, "s-native-apiversions", 5000)
    if problem.code != 0 { println("Kafka connect failed: " + problem.message); return 1 }
    versions, negotiation_error := std.kafka.broker_api_versions(b*, 5000)
    if negotiation_error.code != 0 {
        println("Kafka ApiVersions failed: " + negotiation_error.message)
        std.kafka.broker_close(b*)
        return 2
    }
    found := false
    i := 0
    while i < len(versions) {
        if versions[i].api_key == 18 && versions[i].min_version == 0 && versions[i].max_version >= 0 { found = true }
        i = i + 1
    }
    close_error := std.kafka.broker_close(b*)
    if close_error.code != 0 || !found || len(versions) < 10 || b.correlation_id != 2 { return 3 }
    println("Kafka localhost:9092 ApiVersions v0: correlation=1 validated; API 18 found; socket closed: PASS")
    return 0
}
