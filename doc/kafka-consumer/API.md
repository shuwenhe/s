# Consumer API and ownership

The interfaces below are implemented. See RESULTS.md for acceptance evidence and
current audit findings. The fresh five-path Kafka functional matrix passed;
production memory qualification remains incomplete. See
[capability matrix](../kafka/KAFKA_CAPABILITY_MATRIX.md) and
[memory audit](../kafka/KAFKA_MEMORY_AUDIT.md).

```s
bootstrap := std.kafka.endpoint[]()
bootstrap = append(bootstrap, std.kafka.endpoint { host: "127.0.0.1", port: 9092 })
config := std.kafka.consumer_config { bootstrap: bootstrap, group_id: "orders", auto_commit: false }
c, problem := std.kafka.consumer_new(config)
// Check every error. Subscribe once before servicing/polling.
subscribe_error := std.kafka.consumer_subscribe(c*, string[] { "orders" })
service_error := std.kafka.consumer_service(c*, 100)
close_error := std.kafka.consumer_close(c*, 1000)
```

One owner per open Consumer; do not copy it or call concurrently. At most four
owned role sockets: metadata/bootstrap, group RPC, heartbeat and Fetch. Config
validation is local; network setup/group progress occurs through service/poll.
Current assignment is `c.assigned`; membership/generation/epoch and last error are
observable. Recoverable errors are returned and the state machine can continue
on later calls. State 9 is terminal; state 10 is max-poll-expired pending data poll.

`consumer_service(c*,timeout_ms)` progresses membership/heartbeat/recovery without
implicitly processing records. Call it while processing a delivered batch.
Defaults: session 10000 ms, heartbeat 3000 ms, max-poll interval 300000 ms. Broker
session bounds still apply. Recommended service interval <=1000 ms. A stalled
application without poll/service can lose its session; revocation invalidates old
ownership/delivery epochs. There is no background liveness guarantee.

`consumer_close(c*,timeout_ms)` attempts LeaveGroup with an available connection
or bounded reconnect, then releases all sockets even on failure. Repeated close
is safe. Failed Leave is visible; it is not silently treated as successful departure.

Data and offset interfaces: `consumer_poll` returns one bounded batch plus delivery
token; `consumer_ack` acknowledges the fully processed returned batch;
`consumer_commit` sends only ACK-gated positions; automatic commits use the same
positions. No implicit ACK on poll/service/close. Crash before a confirmed commit
may replay records. Delivery is at least once. A lost commit response leaves the commit outcome unknown;
retrying the same acknowledged position is safe. Caller timeout may leave an
incremental commit pending; poll/service continues it and a subsequent commit waits
for its result. Confirmed offsets advance only for successful response partitions.
Terminal broker authorization errors remain visible. Generation/assignment changes
invalidate tokens and commit snapshots.

`consumer_poll(c*,timeout_ms) (consumer_batch,error)` returns bounded records with
`topic` and `data` (message), `delivery_id` and `assignment_epoch`. A timed out poll
returns an empty batch. Only one delivery may be outstanding; ACK the whole batch
with `consumer_ack(c*,delivery_id)` after processing every record. While processing,
call service regularly. Delivery/prefetch never advances processed positions.
`consumer_commit(c*,timeout_ms)` commits ACKed positions; no candidates is a no-op.
Automatic commits run through poll/service and use exactly the same ACK gate.

`consumer_seek(c*,topic,partition_id,offset)` requires current ownership and a
nonnegative explicit offset. It invalidates the delivery token and queued records,
rewinds other partitions to acknowledged progress, and does not commit the target.
Out-of-range Fetch is explicit; callers may seek to a valid position.

Stable consumers refresh subscribed metadata every 30 seconds and revoke/rejoin
when partition topology changes. Fetch leader errors also trigger recovery.

Synchronous connection attempts are bounded by the caller's budget and, while
membership is held, the remaining session/max-poll deadlines. Other role connects
also yield at the next heartbeat deadline. A heartbeat connection uses ownership
deadlines rather than its already-due scheduling timestamp. Request deadlines are
independent: a short poll/service budget preserves a pending incremental RPC.

Consumer-specific error codes: `error_rebalance=10`, `error_unacknowledged=11`,
`error_poll_interval=12`. Broker errors retain the Kafka error in `native_code`.
Always inspect returned errors; recoverable coordinator/rebalance/transport errors
are observable and later poll/service calls drive rejoin. Unsupported compression,
malformed frames/records and authorization failures are terminal and explicit.

## Audit clarifications — 2026-11-15

- Polling does not ACK. A returned nonempty batch must be fully processed before
  `consumer_ack(c*,batch.delivery_id)`. To commit explicitly after a successful
  ACK, call `consumer_commit(c*,5000)` and inspect its error. Empty/timed-out batches
  have no delivery to ACK. Keep calling service during long processing.
- `consumer_ack` checks local state/token/epoch, but does not itself call the clock
  liveness check. After an unserviced session/max-poll lapse an ACK can succeed
  locally until service/poll observes expiry; this was reproduced by a synthetic
  probe. This is not evidence that a stale generation can commit at the broker.
- `consumer_close` may commit ACKed progress when auto_commit=true. Socket closure
  and delivery invalidation do not imply all managed fields or allocator pages are
  reclaimed. Mid-decode decoder data and commit snapshots remain in a closed
  object; see findings M-01/M-02.
- Config defaults include request_timeout_ms=5000, connect_timeout_ms=1000,
  rebalance_timeout_ms=15000, auto_commit_interval_ms=5000,
  max_poll_records=128, fetch_max_bytes=786432 and initial_offset=0 (earliest).
  initial_offset=1 selects latest only when there is no committed offset.
- fetch_max_bytes is bounded to 1024..786432, while the entire response must fit
  1 MiB and the decoder accumulates at most 4096 records over all included batches.
  max_poll_records bounds delivery size, not decoded storage or native RSS.
  1 MiB payloads and 4160 small records in one valid response fail current caps.
- Subscribe takes 1..64 explicit topic names once before polling. Reopen to change
  subscription; regex, pause/resume and manual assignment APIs are absent.
- Configuration accepts at most 64 bootstrap endpoints, and metadata/assignment
  are bounded to 64 topics/4096 partitions and 128 group members. Host strings in
  bootstrap and broker-advertised endpoints must be literal IPv4 at connect time.
- The RSS size sweep intentionally used request_timeout_ms=30000 to isolate
  allocation from the default deadline; it does not certify large-payload latency
  at the 5000 ms default. Canonical and Seed have different allocator behavior.

Build instructions and test commands are in TESTING.md. The stock benchmark builder
currently globs two main functions; the audit retained the failure and selected
only the intended entrypoint in a copied runner, without changing production code.

Remote-idle close limitation (audit R-02): reconnecting a group socket already known
closed is tested, but a broker-idled socket can still look open locally. If close
discovers EOF during LeaveGroup, it returns a transport error without retrying that
Leave. Fresh real tests reproduced error code 4/native 104 under Seed/canonical.
Sockets are still released by the close cleanup path; this is a failed graceful
Leave/recovery gate, not evidence that every close leaks an FD.
