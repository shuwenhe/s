package std.kafka
func consumer_build_find(string client, int correlation, string group) (string,error) {
    if len(group) < 1 || len(group) > 255 { return "", failure(error_invalid, "invalid consumer group") }
    w := _kc_header(client, correlation, 10, 1)
    put_string(w*, group)
    put_int(w*, 0, 1)
    return w.data, w.failure
}
func consumer_parse_find(string data) (endpoint,error) {
    c := new_cursor(data, 1048576)
    throttle := read_int(c*, 4)
    status := read_int(c*, 2)
    message := read_nullable(c*, 2, 32767)
    id := read_int(c*, 4)
    host := read_string(c*, 255)
    port := read_int(c*, 4)
    problem := finished(c*)
    if problem.code != 0 { return endpoint {}, problem }
    issue := _kc_broker_error(status, "FindCoordinator error")
    if issue.code != 0 { return endpoint {}, issue }
    if throttle < 0 || id < 0 || host == "" || port < 1 || port > 65535 { return endpoint {}, failure(error_protocol, "invalid coordinator endpoint") }
    return endpoint { node_id: id, host: host, port: port }, error {}
}
func consumer_build_join(string client, int correlation, string group, string member, string[] topics, int session_ms, int rebalance_ms) (string,error) {
    if len(group) < 1 || len(group) > 255 || len(member) > 32767 || session_ms < 1000 || rebalance_ms < session_ms { return "", failure(error_invalid, "invalid JoinGroup arguments") }
    subscription, problem := consumer_subscription(topics)
    if problem.code != 0 { return "", problem }
    w := _kc_header(client, correlation, 11, 2)
    put_string(w*, group)
    put_int(w*, session_ms, 4)
    put_int(w*, rebalance_ms, 4)
    put_string(w*, member)
    put_string(w*, "consumer")
    put_int(w*, 1, 4)
    put_string(w*, "range")
    size := len(subscription)
    put_int(w*, size, 4)
    put_raw(w*, subscription)
    return w.data, w.failure
}
func consumer_parse_join(string data) (consumer_join_result,error) {
    result := consumer_join_result {}
    c := new_cursor(data, 1048576)
    throttle := read_int(c*, 4)
    status := read_int(c*, 2)
    result.generation_id = read_int(c*, 4)
    protocol := read_string(c*, 32767)
    result.leader_id = read_string(c*, 32767)
    result.member_id = read_string(c*, 32767)
    count := array_count(c*, 128, false)
    i := 0
    while i < count && c.failure.code == 0 {
        id := read_string(c*, 32767)
        metadata := read_nullable(c*, 4, 1048576)
        if !metadata.present || id == "" { return result, failure(error_protocol, "invalid JoinGroup member") }
        topics, topic_error := consumer_parse_subscription(metadata.data)
        if topic_error.code != 0 { return result, topic_error }
        j := 0
        while j < len(result.members) { if result.members[j].member_id == id { return result, failure(error_protocol, "duplicate JoinGroup member") } j = j + 1 }
        result.members = append(result.members, consumer_member { member_id: id, topics: topics })
        i = i + 1
    }
    problem := finished(c*)
    if problem.code != 0 { return result, problem }
    issue := _kc_broker_error(status, "JoinGroup error")
    if issue.code != 0 { return result, issue }
    if throttle < 0 || result.generation_id < 0 || protocol != "range" || result.member_id == "" || result.leader_id == "" { return result, failure(error_protocol, "invalid JoinGroup result") }
    return result, error {}
}
func consumer_build_sync(string client, int correlation, string group, string member, int generation, member_assignment[] assignments) (string,error) {
    w := _kc_header(client, correlation, 14, 1)
    put_string(w*, group)
    put_int(w*, generation, 4)
    put_string(w*, member)
    count := len(assignments)
    if count > 128 { return "", failure(error_bounds, "SyncGroup member count") }
    put_int(w*, count, 4)
    i := 0
    while i < count {
        a := assignments[i]
        bytes, problem := consumer_assignment_encode(a.partitions)
        if problem.code != 0 { return "", problem }
        put_string(w*, a.member_id)
        size := len(bytes)
        put_int(w*, size, 4)
        put_raw(w*, bytes)
        i = i + 1
    }
    return w.data, w.failure
}
func consumer_parse_sync(string data) (topic_partition[],error) {
    c := new_cursor(data, 1048576)
    throttle := read_int(c*, 4)
    status := read_int(c*, 2)
    bytes := read_nullable(c*, 4, 1048576)
    problem := finished(c*)
    if problem.code != 0 { return topic_partition[](), problem }
    issue := _kc_broker_error(status, "SyncGroup error")
    if issue.code != 0 { return topic_partition[](), issue }
    if throttle < 0 || !bytes.present { return topic_partition[](), failure(error_protocol, "invalid SyncGroup response") }
    return consumer_assignment_parse(bytes.data)
}
func consumer_build_membership(string client, int correlation, string group, string member, int generation, int api) (string,error) {
    if api != 12 && api != 13 { return "", failure(error_invalid, "invalid membership API") }
    w := _kc_header(client, correlation, api, 1)
    put_string(w*, group)
    if api == 12 { put_int(w*, generation, 4) }
    put_string(w*, member)
    return w.data, w.failure
}
func consumer_parse_membership(string data) error {
    c := new_cursor(data, 1048576)
    throttle := read_int(c*, 4)
    status := read_int(c*, 2)
    problem := finished(c*)
    if problem.code != 0 { return problem }
    if throttle < 0 { return failure(error_protocol, "invalid membership throttle") }
    return _kc_broker_error(status, "consumer membership error")
}
