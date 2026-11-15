package std.kafka
struct fetch_records { string data, int high_watermark, int last_stable_offset }
func consumer_build_fetch(string client, int correlation, string topic, int partition_id, int offset, int max_wait_ms, int max_bytes) (string,error) {
    if !_k_topic_valid(topic) || partition_id < 0 || partition_id > 2147483647 || offset < 0 || max_wait_ms < 0 || max_wait_ms > 2147483647 || max_bytes < 1024 || max_bytes > 786432 {
        return "", failure(error_invalid, "invalid Fetch arguments")
    }
    w := _kc_header(client, correlation, 1, 4)
    put_int(w*, -1, 4)
    put_int(w*, max_wait_ms, 4)
    put_int(w*, 1, 4)
    put_int(w*, max_bytes, 4)
    put_int(w*, 0, 1)
    put_int(w*, 1, 4)
    put_string(w*, topic)
    put_int(w*, 1, 4)
    put_int(w*, partition_id, 4)
    put_int(w*, offset, 8)
    put_int(w*, max_bytes, 4)
    return w.data, w.failure
}
func consumer_parse_fetch(string data, string topic, int partition_id) (fetch_records,error) {
    result := fetch_records {}
    c := new_cursor(data, 1048576)
    throttle := read_int(c*, 4)
    topics := read_int(c*, 4)
    name := read_string(c*, 249)
    partitions := read_int(c*, 4)
    id := read_int(c*, 4)
    status := read_int(c*, 2)
    result.high_watermark = read_int(c*, 8)
    result.last_stable_offset = read_int(c*, 8)
    aborted := array_count(c*, 4096, true)
    i := 0
    while i < aborted && c.failure.code == 0 { read_int(c*, 8); read_int(c*, 8); i = i + 1 }
    records := read_nullable(c*, 4, 1048576)
    result.data = records.data
    problem := finished(c*)
    if problem.code != 0 { return fetch_records {}, problem }
    if topics != 1 || partitions != 1 || name != topic || id != partition_id || throttle < 0 { return fetch_records {}, failure(error_protocol, "Fetch response identity") }
    issue := _kc_broker_error(status, "Fetch partition error")
    if issue.code != 0 { return fetch_records {}, issue }
    if result.high_watermark < 0 || result.last_stable_offset < -1 { return fetch_records {}, failure(error_protocol, "Fetch watermark") }
    return result, error {}
}
