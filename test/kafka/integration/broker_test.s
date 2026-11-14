func broker_checks() int {
    b, problem := std.kafka.broker_connect("127.0.0.1", 9092, "s-native-repeat", 5000)
    if problem.code != 0 { return 4 }
    first, first_error := std.kafka.broker_api_versions(b*, 5000)
    second, second_error := std.kafka.broker_api_versions(b*, 5000)
    close_error := std.kafka.broker_close(b*)
    repeated_close := std.kafka.broker_close(b*)
    if first_error.code != 0 || second_error.code != 0 || len(first) != len(second) || len(first) == 0 { return 5 }
    if b.correlation_id != 3 || close_error.code != 0 || repeated_close.code != 0 || b.state != 0 { return 6 }
    println("Kafka consecutive correlations 1/2 and repeated close: PASS")
    return 0
}
