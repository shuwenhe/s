package std.kafka
struct consumer_member { string member_id, string[] topics }
struct member_assignment { string member_id, topic_partition[] partitions }
struct consumer_join_result { int generation_id, string member_id, string leader_id, consumer_member[] members }
func _kc_contains(string[] values, string value) bool {
    i := 0
    while i < len(values) { if values[i] == value { return true } i = i + 1 }
    return false
}
func consumer_subscription(string[] topics) (string,error) {
    if len(topics) < 1 || len(topics) > 64 { return "", failure(error_invalid, "subscription topic count") }
    w := new_writer(1048576)
    put_int(w*, 0, 2)
    count := len(topics)
    put_int(w*, count, 4)
    i := 0
    while i < count {
        topic := topics[i]
        if !_k_topic_valid(topic) { return "", failure(error_invalid, "subscription topic name") }
        j := 0
        while j < i { if topics[j] == topic { return "", failure(error_invalid, "duplicate subscription topic") } j = j + 1 }
        put_string(w*, topic)
        i = i + 1
    }
    put_int(w*, -1, 4)
    return w.data, w.failure
}
func consumer_parse_subscription(string data) (string[],error) {
    topics := string[]()
    c := new_cursor(data, 1048576)
    version := read_int(c*, 2)
    count := array_count(c*, 64, false)
    if version != 0 { return topics, failure(error_unsupported, "consumer subscription version") }
    i := 0
    while i < count && c.failure.code == 0 {
        topic := read_string(c*, 249)
        if !_k_topic_valid(topic) || _kc_contains(topics, topic) { return topics, failure(error_protocol, "invalid subscription topic") }
        topics = append(topics, topic)
        i = i + 1
    }
    userdata := read_nullable(c*, 4, 1048576)
    problem := finished(c*)
    return topics, problem
}
func consumer_assignment_encode(topic_partition[] partitions) (string,error) {
    if len(partitions) > 4096 { return "", failure(error_bounds, "assignment partition cap") }
    topics := string[]()
    i := 0
    while i < len(partitions) {
        p := partitions[i]
        if !_k_topic_valid(p.topic) || p.partition_id < 0 { return "", failure(error_invalid, "assignment partition") }
        if !_kc_contains(topics, p.topic) { topics = append(topics, p.topic) }
        i = i + 1
    }
    if len(topics) > 64 { return "", failure(error_bounds, "assignment topic cap") }
    w := new_writer(1048576)
    put_int(w*, 0, 2)
    count := len(topics)
    put_int(w*, count, 4)
    i = 0
    while i < count {
        topic := topics[i]
        put_string(w*, topic)
        n := 0
        j := 0
        while j < len(partitions) { if partitions[j].topic == topic { n = n + 1 } j = j + 1 }
        put_int(w*, n, 4)
        j = 0
        while j < len(partitions) {
            p := partitions[j]
            if p.topic == topic { put_int(w*, p.partition_id, 4) }
            j = j + 1
        }
        i = i + 1
    }
    put_int(w*, -1, 4)
    return w.data, w.failure
}
func consumer_assignment_parse(string data) (topic_partition[],error) {
    parts := topic_partition[]()
    topics := string[]()
    c := new_cursor(data, 1048576)
    version := read_int(c*, 2)
    count := array_count(c*, 64, false)
    if version != 0 { return parts, failure(error_unsupported, "consumer assignment version") }
    i := 0
    while i < count && c.failure.code == 0 {
        topic := read_string(c*, 249)
        if !_k_topic_valid(topic) || _kc_contains(topics, topic) { return parts, failure(error_protocol, "invalid assignment topic") }
        topics = append(topics, topic)
        n := array_count(c*, 4096, false)
        j := 0
        while j < n && c.failure.code == 0 {
            id := read_int(c*, 4)
            if id < 0 || len(parts) >= 4096 { return parts, failure(error_bounds, "invalid assignment partition count") }
            k := 0
            while k < len(parts) { if parts[k].topic == topic && parts[k].partition_id == id { return parts, failure(error_protocol, "duplicate assigned partition") } k = k + 1 }
            parts = append(parts, topic_partition { topic: topic, partition_id: id, committed_offset: -1 })
            j = j + 1
        }
        i = i + 1
    }
    userdata := read_nullable(c*, 4, 1048576)
    problem := finished(c*)
    return parts, problem
}
func consumer_range_assign(consumer_member[] source, consumer_metadata meta) (member_assignment[],error) {
    out := member_assignment[]()
    if len(source) < 1 || len(source) > 128 { return out, failure(error_bounds, "group member count") }
    members := source
    i := 0
    while i < len(members) {
        if members[i].member_id == "" { return out, failure(error_protocol, "empty group member") }
        j := i + 1
        while j < len(members) {
            if members[i].member_id == members[j].member_id { return out, failure(error_protocol, "duplicate group member") }
            if members[i].member_id > members[j].member_id { swap := members[i]; members[i] = members[j]; members[j] = swap }
            j = j + 1
        }
        out = append(out, member_assignment { member_id: members[i].member_id })
        i = i + 1
    }
    i = 0
    while i < len(meta.topics) {
        topic := meta.topics[i]
        ids := int[]()
        j := 0
        while j < len(meta.partitions) { p := meta.partitions[j]; if p.topic == topic { ids = append(ids, p.partition_id) } j = j + 1 }
        j = 0
        while j < len(ids) {
            k := j + 1
            while k < len(ids) { if ids[j] > ids[k] { swap := ids[j]; ids[j] = ids[k]; ids[k] = swap } k = k + 1 }
            j = j + 1
        }
        eligible := int[]()
        j = 0
        while j < len(members) { if _kc_contains(members[j].topics, topic) { eligible = append(eligible, j) } j = j + 1 }
        if len(eligible) == 0 { return out, failure(error_protocol, "topic has no subscribed member") }
        position := 0
        j = 0
        while j < len(eligible) {
            n := len(ids) / len(eligible)
            if j < len(ids) % len(eligible) { n = n + 1 }
            index := eligible[j]
            assignment := out[index]
            k := 0
            while k < n { assignment.partitions = append(assignment.partitions, topic_partition { topic: topic, partition_id: ids[position], committed_offset: -1 }); position = position + 1; k = k + 1 }
            out[index] = assignment
            j = j + 1
        }
        i = i + 1
    }
    return out, error {}
}
