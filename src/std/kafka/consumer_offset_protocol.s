package std.kafka
struct consumer_offset_result { string topic, int partition_id, int offset, int timestamp_ms, int status }
func consumer_partition_index(topic_partition[] parts, string topic, int id) int {
    i := 0
    while i < len(parts) { if parts[i].topic == topic && parts[i].partition_id == id { return i } i = i + 1 }
    return -1
}
func _kc_partition_topics(topic_partition[] parts) (string[],error) {
    topics := string[]()
    if len(parts) > 4096 { return topics, failure(error_bounds, "offset partition cap") }
    i := 0
    while i < len(parts) {
        p := parts[i]
        if !_k_topic_valid(p.topic) || p.partition_id < 0 { return topics, failure(error_invalid, "offset partition") }
        if !_kc_contains(topics, p.topic) { topics = append(topics, p.topic) }
        j := 0
        while j < i { if parts[j].topic == p.topic && parts[j].partition_id == p.partition_id { return topics, failure(error_invalid, "duplicate offset partition") } j = j + 1 }
        i = i + 1
    }
    if len(topics) > 64 { return topics, failure(error_bounds, "offset topic cap") }
    return topics, error {}
}
func consumer_build_offset_commit(string client, int correlation, string group, string member, int generation, topic_partition[] parts) (string,error) {
    return _kc_build_offsets(client, correlation, group, member, generation, parts, 8, 0)
}
func consumer_build_offset_fetch(string client, int correlation, string group, topic_partition[] parts) (string,error) {
    return _kc_build_offsets(client, correlation, group, "", 0, parts, 9, 0)
}
func consumer_build_list_offsets(string client, int correlation, topic_partition[] parts, int timestamp) (string,error) {
    if timestamp < -2 { return "", failure(error_invalid, "ListOffsets timestamp") }
    return _kc_build_offsets(client, correlation, "", "", 0, parts, 2, timestamp)
}
func _kc_build_offsets(string client, int correlation, string group, string member, int generation, topic_partition[] parts, int api, int timestamp) (string,error) {
    topics, problem := _kc_partition_topics(parts)
    if problem.code != 0 { return "", problem }
    version := 2
    if api == 2 { version = 1 }
    w := _kc_header(client, correlation, api, version)
    if api == 2 { put_int(w*, -1, 4) } else { put_string(w*, group) }
    if api == 8 {
        put_int(w*, generation, 4)
        put_string(w*, member)
        put_int(w*, -1, 8)
    }
    count := len(topics)
    put_int(w*, count, 4)
    i := 0
    while i < count {
        topic := topics[i]
        put_string(w*, topic)
        n := 0
        j := 0
        while j < len(parts) { if parts[j].topic == topic { n = n + 1 } j = j + 1 }
        put_int(w*, n, 4)
        j = 0
        while j < len(parts) {
            p := parts[j]
            if p.topic == topic {
                put_int(w*, p.partition_id, 4)
                if api == 2 { put_int(w*, timestamp, 8) }
                if api == 8 {
                    if p.offset < 0 { return "", failure(error_invalid, "negative commit offset") }
                    put_int(w*, p.offset, 8)
                    put_int(w*, -1, 2)
                }
            }
            j = j + 1
        }
        i = i + 1
    }
    return w.data, w.failure
}
func consumer_parse_offsets(string data, topic_partition[] expected, int api) (consumer_offset_result[],error) {
    results := consumer_offset_result[]()
    if api != 2 && api != 8 && api != 9 { return results, failure(error_invalid, "offset response API") }
    c := new_cursor(data, 1048576)
    topics := array_count(c*, 64, false)
    issue := error {}
    i := 0
    while i < topics && c.failure.code == 0 {
        topic := read_string(c*, 249)
        count := array_count(c*, 4096, false)
        j := 0
        while j < count && c.failure.code == 0 {
            id := read_int(c*, 4)
            offset := -1
            timestamp := -1
            status := 0
            if api == 9 {
                offset = read_int(c*, 8)
                metadata := read_nullable(c*, 2, 32767)
                status = read_int(c*, 2)
            } else {
                status = read_int(c*, 2)
                if api == 2 { timestamp = read_int(c*, 8); offset = read_int(c*, 8) }
            }
            if consumer_partition_index(expected, topic, id) < 0 { return consumer_offset_result[](), failure(error_protocol, "unexpected offset response partition") }
            k := 0
            while k < len(results) { if results[k].topic == topic && results[k].partition_id == id { return consumer_offset_result[](), failure(error_protocol, "duplicate offset response partition") } k = k + 1 }
            if offset < -1 { return consumer_offset_result[](), failure(error_protocol, "invalid offset response position") }
            results = append(results, consumer_offset_result { topic: topic, partition_id: id, offset: offset, timestamp_ms: timestamp, status: status })
            if status != 0 && (issue.code == 0 || _kc_offset_error_rank(status) > _kc_offset_error_rank(issue.native_code)) { issue = _kc_broker_error(status, "consumer offset broker error") }
            j = j + 1
        }
        i = i + 1
    }
    global_status := 0
    if api == 9 { global_status = read_int(c*, 2) }
    problem := finished(c*)
    if problem.code != 0 { return consumer_offset_result[](), problem }
    if global_status != 0 {
        if issue.code == 0 || _kc_offset_error_rank(global_status) > _kc_offset_error_rank(issue.native_code) { issue = _kc_broker_error(global_status, "OffsetFetch coordinator error") }
        return results, issue
    }
    if len(results) != len(expected) { return consumer_offset_result[](), failure(error_protocol, "offset response omitted partitions") }
    return results, issue
}
