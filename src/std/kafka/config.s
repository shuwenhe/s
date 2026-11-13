package std.kafka

import "std.prelude"

struct endpoint {
    string host
    int port
    int node_id
}

struct config {
    endpoint[] bootstrap
    string client_id
    int connect_timeout_ms
    int read_timeout_ms
    int write_timeout_ms
    int request_timeout_ms
    int max_frame_bytes
    int max_records
    int acknowledgments
    bool use_tls
    string tls_server_name
    string tls_ca_file
}

struct nullable_bytes {
    bool present
    string data
}

struct header {
    string key
    nullable_bytes value
}

struct message {
    nullable_bytes key
    nullable_bytes value
    header[] headers
    int timestamp_ms
    int offset
    int partition
}

struct message_set {
    message[] records
    int count
    int next_offset
}

struct partition {
    int id
    int leader_id
    int status
}

struct metadata {
    endpoint[] brokers
    partition[] partitions
    string topic
    int controller_id
}

struct produce_result {
    int partition
    int offset
    int timestamp_ms
}

func bytes(string value) nullable_bytes {
    return nullable_bytes { present: true, data: value }
}

func _k_config(config source) (config, error) {
    c := source
    if len(c.bootstrap) == 0 || len(c.bootstrap) > 64 {
        return c, failure(error_invalid, "provide 1..64 bootstrap brokers")
    }
    if c.client_id == "" {
        c.client_id = "s-native-kafka"
    }
    if c.connect_timeout_ms == 0 {
        c.connect_timeout_ms = 5000
    }
    if c.read_timeout_ms == 0 {
        c.read_timeout_ms = 5000
    }
    if c.write_timeout_ms == 0 {
        c.write_timeout_ms = 5000
    }
    if c.request_timeout_ms == 0 {
        c.request_timeout_ms = 3000
    }
    if c.max_frame_bytes == 0 {
        c.max_frame_bytes = 1048576
    }
    if c.max_records == 0 {
        c.max_records = 4096
    }
    if c.acknowledgments == 0 {
        c.acknowledgments = -1
    }
    if len(c.client_id) > 256 || c.max_frame_bytes < 1024 || c.max_frame_bytes > 16777216 ||
        c.max_records < 1 || c.max_records > 65536 ||
        c.connect_timeout_ms < 1 || c.connect_timeout_ms > 2147483647 ||
        c.read_timeout_ms < 1 || c.read_timeout_ms > 2147483647 ||
        c.write_timeout_ms < 1 || c.write_timeout_ms > 2147483647 ||
        c.request_timeout_ms < 1 || c.request_timeout_ms > 2147483647 ||
        (c.acknowledgments != 1 && c.acknowledgments != -1) {
        return c, failure(error_invalid, "invalid Kafka configuration")
    }
    if c.use_tls && c.tls_server_name == "" {
        return c, failure(error_invalid, "TLS requires a verified server name")
    }
    i := 0
    while i < len(c.bootstrap) {
        if c.bootstrap[i].host == "" || c.bootstrap[i].port < 1 || c.bootstrap[i].port > 65535 {
            return c, failure(error_invalid, "invalid bootstrap endpoint")
        }
        i = i + 1
    }
    return c, error {}
}
