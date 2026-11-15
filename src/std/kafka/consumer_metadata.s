package std.kafka

struct topic_partition {
    string topic
    int partition_id
    int leader_id
    int offset
    int processed_offset
    int committed_offset
    bool processed_valid
}
struct consumer_metadata {
    endpoint[] brokers
    topic_partition[] partitions
    string[] topics
    int controller_id
}
func consumer_build_metadata(string client, int correlation, string[] topics) (string, error) {
    if len(topics) < 1 || len(topics) > 64 { return "", failure(error_invalid, "consumer topic count") }
    w := _kc_header(client, correlation, 3, 4)
    count := len(topics)
    put_int(w*, count, 4)
    i := 0
    while i < count {
        topic := topics[i]
        if !_k_topic_valid(topic) { return "", failure(error_invalid, "invalid consumer topic") }
        j := 0
        while j < i { if topics[j] == topic { return "", failure(error_invalid, "duplicate consumer topic") } j = j + 1 }
        put_string(w*, topic)
        i = i + 1
    }
    put_int(w*, 0, 1)
    return w.data, w.failure
}
func consumer_parse_metadata(string data) (consumer_metadata, error) {
    result := consumer_metadata {}
    c := new_cursor(data, 1048576)
    throttle := read_int(c*, 4)
    brokers := array_count(c*, 64, false)
    i := 0
    while i < brokers && c.failure.code == 0 {
        id := read_int(c*, 4)
        host := read_string(c*, 255)
        port := read_int(c*, 4)
        rack := read_nullable(c*, 2, 32767)
        if id < 0 || len(host) == 0 || port < 1 || port > 65535 { return result, failure(error_protocol, "invalid metadata broker") }
        j := 0
        while j < len(result.brokers) { if result.brokers[j].node_id == id { return result, failure(error_protocol, "duplicate metadata broker") } j = j + 1 }
        result.brokers = append(result.brokers, endpoint { node_id: id, host: host, port: port })
        i = i + 1
    }
    cluster := read_nullable(c*, 2, 32767)
    result.controller_id = read_int(c*, 4)
    topics := array_count(c*, 64, false)
    issue := error {}
    i = 0
    while i < topics && c.failure.code == 0 {
        status := read_int(c*, 2)
        topic := read_string(c*, 249)
        internal := read_int(c*, 1)
        count := array_count(c*, 4096, false)
        if internal < 0 || internal > 1 || !_k_topic_valid(topic) { return result, failure(error_protocol, "invalid metadata topic") }
        j := 0
        while j < len(result.topics) { if result.topics[j] == topic { return result, failure(error_protocol, "duplicate metadata topic") } j = j + 1 }
        result.topics = append(result.topics, topic)
        if status != 0 && issue.code == 0 { issue = _kc_broker_error(status, "Metadata topic error") }
        j = 0
        while j < count && c.failure.code == 0 {
            partition_error := read_int(c*, 2)
            id := read_int(c*, 4)
            leader := read_int(c*, 4)
            replicas := array_count(c*, 64, false)
            k := 0
            while k < replicas && c.failure.code == 0 { read_int(c*, 4); k = k + 1 }
            isr := array_count(c*, 64, false)
            k = 0
            while k < isr && c.failure.code == 0 { read_int(c*, 4); k = k + 1 }
            if id < 0 || leader < -1 || len(result.partitions) >= 4096 { return result, failure(error_protocol, "invalid metadata partition") }
            k = 0
            while k < len(result.partitions) {
                p := result.partitions[k]
                if p.topic == topic && p.partition_id == id { return result, failure(error_protocol, "duplicate metadata partition") }
                k = k + 1
            }
            if partition_error != 0 && issue.code == 0 { issue = _kc_broker_error(partition_error, "Metadata partition error") }
            result.partitions = append(result.partitions, topic_partition { topic: topic, partition_id: id, leader_id: leader, committed_offset: -1 })
            j = j + 1
        }
        i = i + 1
    }
    problem := finished(c*)
    if problem.code != 0 { return consumer_metadata {}, problem }
    if throttle < 0 { return consumer_metadata {}, failure(error_protocol, "negative metadata throttle") }
    return result, issue
}
func consumer_metadata_endpoint(consumer_metadata meta, int node_id) (endpoint, error) {
    i := 0
    while i < len(meta.brokers) {
        if meta.brokers[i].node_id == node_id { return meta.brokers[i], error {} }
        i = i + 1
    }
    return endpoint {}, failure(error_protocol, "metadata leader not found")
}

// Compare subscribed topology independently of broker/topic response ordering.
func consumer_metadata_changed(consumer_metadata before, consumer_metadata after, string[] topics) bool {
    old_count := 0
    new_count := 0
    i := 0
    while i < len(before.partitions) {
        p := before.partitions[i]
        if _kc_contains(topics, p.topic) {
            old_count = old_count + 1
            found := false
            j := 0
            while j < len(after.partitions) {
                q := after.partitions[j]
                if p.topic == q.topic && p.partition_id == q.partition_id && p.leader_id == q.leader_id { found = true }
                j = j + 1
            }
            if !found { return true }
        }
        i = i + 1
    }
    i = 0
    while i < len(after.partitions) { if _kc_contains(topics, after.partitions[i].topic) { new_count = new_count + 1 } i = i + 1 }
    return old_count != new_count
}
