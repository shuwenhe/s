package std.kafka
const error_rebalance = 10
const error_unacknowledged = 11
const error_poll_interval = 12
struct consumer_config {
    endpoint[] bootstrap
    string client_id
    string group_id
    bool auto_commit
    int auto_commit_interval_ms
    int session_timeout_ms
    int heartbeat_interval_ms
    int rebalance_timeout_ms
    int request_timeout_ms
    int connect_timeout_ms
    int max_poll_interval_ms
    int max_poll_records
    int fetch_max_bytes
    int initial_offset
}
struct consumed_record { string topic, message data }
struct consumer_batch { consumed_record[] records, int delivery_id, int assignment_epoch, bool timed_out }
struct consumer {
    consumer_config config
    bool initialized
    bool closed
    int state
    string[] topics
    string[] metadata_topics
    consumer_metadata metadata
    topic_partition[] assigned
    consumer_join_result joined
    endpoint coordinator
    string member_id
    int generation_id
    int assignment_epoch
    consumer_link bootstrap_link
    consumer_link group_link
    consumer_link heartbeat_link
    consumer_link fetch_link
    int bootstrap_operation
    int group_operation
    int fetch_operation
    int bootstrap_index
    int next_partition
    int fetch_partition
    int next_heartbeat_ns
    int last_heartbeat_ns
    int last_poll_ns
    int next_metadata_ns
    int retry_at_ns
    last_error: error
    consumer_decoder decoder
    message[] queue
    int queue_cursor
    int queue_partition
    int queue_end_offset
    int next_delivery_id
    int outstanding_delivery_id
    int outstanding_epoch
    int outstanding_partition
    int outstanding_end_offset
    int next_commit_ns
    topic_partition[] commit_snapshot
    int commit_sequence
    int commit_completed
    int commit_epoch
    int commit_generation
    commit_error: error
    bool offsets_loaded
    bool coordinator_retry
    leave_error: error
}
func consumer_new(consumer_config source) (consumer,error) {
    cfg := source
    c := consumer { generation_id: -1 }
    if cfg.client_id == "" { cfg.client_id = "s-native-consumer" }
    if cfg.session_timeout_ms == 0 { cfg.session_timeout_ms = 10000 }
    if cfg.heartbeat_interval_ms == 0 { cfg.heartbeat_interval_ms = 3000 }
    if cfg.rebalance_timeout_ms == 0 { cfg.rebalance_timeout_ms = 15000 }
    if cfg.request_timeout_ms == 0 { cfg.request_timeout_ms = 5000 }
    if cfg.connect_timeout_ms == 0 { cfg.connect_timeout_ms = 1000 }
    if cfg.max_poll_interval_ms == 0 { cfg.max_poll_interval_ms = 300000 }
    if cfg.max_poll_records == 0 { cfg.max_poll_records = 128 }
    if cfg.fetch_max_bytes == 0 { cfg.fetch_max_bytes = 786432 }
    if cfg.auto_commit_interval_ms == 0 { cfg.auto_commit_interval_ms = 5000 }
    if len(cfg.bootstrap) < 1 || len(cfg.bootstrap) > 64 || len(cfg.client_id) > 32767 || len(cfg.group_id) < 1 || len(cfg.group_id) > 255 ||
        cfg.session_timeout_ms < 3000 || cfg.session_timeout_ms > 2147483647 || cfg.heartbeat_interval_ms < 1000 || cfg.heartbeat_interval_ms > cfg.session_timeout_ms / 3 ||
        cfg.rebalance_timeout_ms < cfg.session_timeout_ms || cfg.rebalance_timeout_ms > 2147483647 - cfg.request_timeout_ms || cfg.request_timeout_ms < 1 ||
        cfg.connect_timeout_ms < 1 || cfg.connect_timeout_ms > cfg.request_timeout_ms || cfg.max_poll_interval_ms < 1000 || cfg.max_poll_interval_ms > 2147483647 ||
        cfg.max_poll_records < 1 || cfg.max_poll_records > 4096 || cfg.fetch_max_bytes < 1024 || cfg.fetch_max_bytes > 786432 ||
        cfg.auto_commit_interval_ms < 1 || cfg.auto_commit_interval_ms > 2147483647 || cfg.initial_offset < 0 || cfg.initial_offset > 1 {
        return c, failure(error_invalid, "invalid consumer configuration")
    }
    i := 0
    while i < len(cfg.bootstrap) {
        e := cfg.bootstrap[i]
        if e.host == "" || e.port < 1 || e.port > 65535 { return c, failure(error_invalid, "invalid consumer bootstrap endpoint") }
        i = i + 1
    }
    c.config = cfg
    c.initialized = true
    c.next_delivery_id = 1
    return c, error {}
}
