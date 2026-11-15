# Native Kafka Producer and Consumer API

Linux/amd64, native S TCP, literal IPv4, sequential calls. No Java/C++ client
library or OpenSSL is linked into the freestanding producer executable.

```s
p, problem := std.kafka.producer_open("127.0.0.1", 9092, "my-client", 5000)
// Check problem.code before continuing. Endpoint must lead the chosen partition.
record := std.kafka.message {
    key: std.kafka.bytes("order-1"),
    value: std.kafka.bytes("created"),
    timestamp_ms: 1794708000000
}
result, publish_error := std.kafka.producer_publish(p*, "orders", 0, record, -1, 5000)
close_error := std.kafka.producer_close(p*)
```

- `producer_open(host, port, client_id, timeout_ms)` connects and requires the
  broker's ApiVersions v0 advertisement to include Produce v3. Connect and
  negotiation each use the supplied timeout. Failed opening releases its socket.
- `producer_publish(p*, topic, partition_id, record, acks, timeout_ms)` publishes
  one record; `producer_publish_batch(..., message[] records, ...)` publishes
  one atomic uncompressed magic-2 RecordBatch to one topic/partition.
- `producer_close(p*)` releases ownership and may be called repeatedly. Do not
  copy an open producer or use it concurrently. Reopen explicitly after failure.
- `acks=-1` waits for the in-sync replicas, `acks=1` waits for the leader,
  `acks=0` completes after the socket write without reading a response. ACK=0
  success does **not** prove broker acceptance or persistence; offset stays -1.
  ACK choices are explicit parameters; the older internal `_k_config` defaults
  are not used by this API.
- An acknowledged `produce_result.offset` is the batch's **base** offset;
  record `i` has offset `base+i`. `timestamp_ms` is the broker log-append time,
  or -1 for CreateTime topics. `partition` is the requested partition.
- Records use explicit nonnegative epoch-millisecond timestamps, including zero.
  Use `std.time.wall_clock()` and divide its nanoseconds by 1000000 for current
  timestamps. Broker timestamp policies still apply. The codec supports the full
  nonnegative int64 range; the server can reject timestamps outside its policy.
- `nullable_bytes {}` represents null. `bytes("")` is present and empty.
  Embedded NULs and other binary bytes in values/keys/header values are preserved.
  Header keys are strings; duplicate keys and null/empty header values are kept.
  Message `offset` and `partition` fields are ignored on publication: partition
  comes from the call and offsets are assigned by Kafka.
- Limits: 1..4096 records, at most 4096 headers per record, 249-byte Kafka topic
  names, 32767-byte client ID, and 1 MiB for the **entire unframed request**.
  Framing adds four bytes. A batch at the codec's 1 MiB ceiling will not fit in
  a Produce request; the builder rejects it locally. Timeout: 1..INT32_MAX ms.
- Serialization happens before the exchange timeout begins. The exchange budget
  bounds write + response header/body + response parsing; the wire TimeoutMs is
  the same supplied value. Read/write/parse failures close the connection.
- Invalid local input leaves a healthy socket and correlation ID unchanged.
  Malformed/framing/correlation errors close it. A valid Kafka error keeps the
  connection open and preserves the signed broker code in `error.native_code`.
  Wrong partition leader (6), unknown topic/partition (3), and all other broker
  errors are returned without automatic retry.

A timeout, partial write, connection loss, or broker error may represent ambiguous
or partial durability. There is no automatic retry or deduplication guarantee.

`build_produce_request(...) (string,error)`, `parse_produce_response(body,topic,
partition_id) (produce_result,error)`, `encode_record_batch(message[]) (string,error)`
and `validate_record_batch(string) error` expose bounded codecs. Validation covers
one producer-format batch (including CRC32C, lengths, record boundaries, timestamps
and offsets); it is not a consumer API and does not accept broker-rewritten or
compressed batches. `broker_connect`, `broker_api_versions`, `broker_send_request`
and `broker_close` remain available for low-level non-flexible requests.

## Consumer

The native Consumer is implemented: Metadata/Fetch, classic eager Range groups,
cooperative heartbeats, rebalance/recovery, explicit ACK, manual/automatic
ACK-gated commits, offset restoration, seek and dynamic partition discovery.
Fresh audit tests separately invoked Seed, canonical and Stage2/3/4 against Kafka
3.9.1. See [capability and evidence matrix](../../../doc/kafka/KAFKA_CAPABILITY_MATRIX.md).

```s
bootstrap := std.kafka.endpoint[]()
bootstrap = append(bootstrap, std.kafka.endpoint { host: "127.0.0.1", port: 9092 })
config := std.kafka.consumer_config { bootstrap: bootstrap, group_id: "orders", auto_commit: false }
c, problem := std.kafka.consumer_new(config)
// Check every error before proceeding.
subscribe_error := std.kafka.consumer_subscribe(c*, string[] { "orders" })
batch, poll_error := std.kafka.consumer_poll(c*, 200)
// After successful polling and processing EVERY returned record:
// consumer_ack(c*, batch.delivery_id), then consumer_commit(c*, 5000).
// During processing call consumer_service(c*, 100) regularly for heartbeats.
close_error := std.kafka.consumer_close(c*, 3000)
```

The snippet shows API shapes; applications must loop poll/service until membership
and data are ready and handle every returned error. An empty poll is normal.
One owner, no concurrent calls or copying. Only one delivery may be outstanding.
Fetch/delivery do not acknowledge processing. Commit only confirms ACKed offsets;
lost responses can leave outcome unknown, and crash/restart can replay records.
No exactly-once guarantee. With auto-commit enabled, close may commit already-ACKed
progress before attempting LeaveGroup; it never implicitly ACKs a delivery.

Consumer scope: uncompressed magic-2, read-uncommitted, <=64 bootstrap endpoints,
<=64 topics, <=128 group members, <=4096 assigned partitions/decoded records per
response, max_poll_records 1..4096, Fetch requested bytes 1024..786432, full response
cap 1 MiB. Delivery count is not a whole-process memory limit. A 1 MiB payload
cannot fit with protocol overhead and was rejected in the fresh audit.

**Known memory limitation:** Seed retained about 704 MiB after 16 repeated 512 KiB
Consumer deliveries; canonical peaked around 48 MiB in the same size case.
ACK/commit/close do not guarantee RSS returns to baseline. See the measured
[memory audit](../../../doc/kafka/KAFKA_MEMORY_AUDIT.md), including the sustained run
and allocator differences, before choosing deployment limits.

A real remote-idle socket test also found that graceful close can fail with
read/EOF instead of reconnecting for LeaveGroup (R-02). Inspect close errors.

Consumer API/ownership details: [API](../../../doc/kafka-consumer/API.md).
Tests and commands: [testing](../../../doc/kafka-consumer/TESTING.md) and
[test README](../../../test/kafka/README.md). Build native tests with
`sh misc/scripts/build-kafka-broker-test.sh consumer-unit NEW_DIR/unit`.
The stock consumer-benchmark wildcard currently includes a second main entrypoint;
the audit's isolated runner selects `main.s` explicitly. See finding T-01.

## Unsupported scope

TLS/SASL, DNS/IPv6 endpoints, compression, Producer automatic metadata/leader
routing, automatic Producer retry/recovery, idempotent production, transactions,
read-committed filtering, background heartbeats, cooperative/static/new-protocol
groups, general connection pooling and quota-aware scheduling remain unsupported.
The Consumer does have multi-broker Metadata discovery and selected leader/
coordinator recovery; these are not Producer features. Producer calls must connect
directly to a known partition leader.

Protocol references: Apache Kafka 3.9.1
[ProduceRequest schema](https://github.com/apache/kafka/blob/3.9.1/clients/src/main/resources/common/message/ProduceRequest.json)
and [ProduceResponse schema](https://github.com/apache/kafka/blob/3.9.1/clients/src/main/resources/common/message/ProduceResponse.json).
