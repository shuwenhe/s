package std.kafka
import "std.time"

// Sequential, single-owner producer for an explicitly supplied partition leader.
// Do not copy an open producer. No automatic retry: a timeout/write failure may
// mean the broker already accepted the batch. Compression/idempotence/transactions
// and automatic metadata/leader routing are unsupported.
struct producer {
    broker connection
    int produce_version
}

func producer_open(string host, int port, string client_id, int timeout_ms) (producer, error) {
    p := producer { produce_version: -1 }
    b, problem := broker_connect(host, port, client_id, timeout_ms)
    if problem.code != 0 { return p, problem }
    versions, negotiation_error := broker_api_versions(b*, timeout_ms)
    if negotiation_error.code != 0 { broker_close(b*); return p, negotiation_error }
    supported := false
    i := 0
    while i < len(versions) {
        v := versions[i]
        if v.api_key == 0 && v.min_version <= 3 && v.max_version >= 3 { supported = true }
        i = i + 1
    }
    if !supported {
        broker_close(b*)
        return p, failure(error_unsupported, "broker does not support Produce v3")
    }
    p.connection = b
    p.produce_version = 3
    return p, error {}
}
func producer_close(producer* p) error {
    b := p.connection
    problem := broker_close(b*)
    p.connection = b
    p.produce_version = -1
    return problem
}
func _k_topic_valid(string topic) bool {
    if len(topic) < 1 || len(topic) > 249 || topic == "." || topic == ".." { return false }
    i := 0
    while i < len(topic) {
        b := __host_byte_at(topic, i)
        if !((b >= 65 && b <= 90) || (b >= 97 && b <= 122) || (b >= 48 && b <= 57) || b == 46 || b == 95 || b == 45) { return false }
        i = i + 1
    }
    return true
}

// Builds one topic/partition request. Acks are explicit: -1=ISR, 1=leader,
// 0=send only. Timeout applies to broker acknowledgment and the transport budget.
func build_produce_request(string client_id, int correlation_id, string topic, int partition_id, message[] records, int acks, int timeout_ms) (string, error) {
    if !_k_topic_valid(topic) || partition_id < 0 || partition_id > 2147483647 ||
        correlation_id < 1 || correlation_id > 2147483647 || len(client_id) > 32767 ||
        (acks != -1 && acks != 0 && acks != 1) || timeout_ms < 1 || timeout_ms > 2147483647 {
        return "", failure(error_invalid, "invalid Produce arguments")
    }
    batch, problem := encode_record_batch(records)
    if problem.code != 0 { return "", problem }
    w := new_writer(1048576)
    put_int(w*, 0, 2)
    put_int(w*, 3, 2)
    put_int(w*, correlation_id, 4)
    put_string(w*, client_id)
    put_int(w*, -1, 2)
    put_int(w*, acks, 2)
    put_int(w*, timeout_ms, 4)
    put_int(w*, 1, 4)
    put_string(w*, topic)
    put_int(w*, 1, 4)
    put_int(w*, partition_id, 4)
    size := len(batch)
    put_int(w*, size, 4)
    put_raw(w*, batch)
    if w.failure.code != 0 { return "", w.failure }
    return w.data, error {}
}

// Body only: correlation/framing are validated by the broker transport.
func parse_produce_response(string data, string topic, int partition_id) (produce_result, error) {
    result := produce_result { partition: partition_id, offset: -1, timestamp_ms: -1 }
    c := new_cursor(data, 1048576)
    topics := read_int(c*, 4)
    name := read_string(c*, 249)
    partitions := read_int(c*, 4)
    index := read_int(c*, 4)
    status := read_int(c*, 2)
    offset := read_int(c*, 8)
    timestamp := read_int(c*, 8)
    throttle := read_int(c*, 4)
    problem := finished(c*)
    if problem.code != 0 { return result, problem }
    if topics != 1 || name != topic || partitions != 1 || index != partition_id || throttle < 0 {
        return result, failure(error_protocol, "mismatched Produce response")
    }
    if status != 0 {
        return result, error { code: error_broker, native_code: status, message: "Produce broker error" }
    }
    if offset < 0 || timestamp < -1 { return result, failure(error_protocol, "invalid Produce offset or timestamp") }
    result.offset = offset
    result.timestamp_ms = timestamp
    return result, error {}
}

// Returns the batch base offset, not its final record offset. ACK=0 returns -1:
// successful socket write does not establish broker acceptance or persistence.
// Caller input errors consume no correlation ID and leave the connection usable.
func producer_publish_batch(producer* p, string topic, int partition_id, message[] records, int acks, int timeout_ms) (produce_result, error) {
    result := produce_result { partition: partition_id, offset: -1, timestamp_ms: -1 }
    b := p.connection
    if b.state != 2 { return result, failure(error_closed, "Kafka producer is closed") }
    if p.produce_version != 3 { return result, failure(error_unsupported, "Produce v3 was not negotiated") }
    request, problem := build_produce_request(b.client_id, b.correlation_id, topic, partition_id, records, acks, timeout_ms)
    if problem.code != 0 { return result, problem }
    now, clock_error := std.time.monotonic_clock()
    if clock_error.code != 0 { return result, _k_network_error(clock_error.code, "Produce clock failed") }
    deadline := now + timeout_ms * 1000000
    body, transport_error := _k_exchange(b*, request, timeout_ms, acks != 0)
    p.connection = b
    if transport_error.code != 0 { return result, transport_error }
    if acks == 0 { return result, error {} }
    parsed, parse_error := parse_produce_response(body, topic, partition_id)
    remaining, timeout_error := _k_remaining(deadline)
    if timeout_error.code != 0 { parse_error = timeout_error }
    if parse_error.code != 0 && parse_error.code != error_broker {
        aborted := _k_abort(b*, parse_error)
        p.connection = b
        return result, aborted
    }
    return parsed, parse_error
}
func producer_publish(producer* p, string topic, int partition_id, message record, int acks, int timeout_ms) (produce_result, error) {
    records := message[]()
    records = append(records, record)
    return producer_publish_batch(p*, topic, partition_id, records, acks, timeout_ms)
}
