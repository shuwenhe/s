# Native Kafka Consumer design — proposed, awaiting approval

Target: Apache Kafka 3.9.1. This document describes proposed behavior, not
implemented support. No Consumer source code is changed before approval.

## 1. Intent and constraints

Deliver a bounded, native S Consumer with metadata/leader discovery, classic
consumer groups, native RecordBatch v2 decoding, manual/automatic offset commits,
restart recovery and explicit at-least-once processing semantics. Preserve the
existing Producer v3 and all existing evidence. No Java Kafka client, librdkafka,
external Kafka client library, system Java installation or compiler/runtime change.
Java runs only repository-local Kafka servers/admin tools in the test harness.

The requested scope is one project spanning protocol codecs, resumable transport,
record decoding, group state and offset management. These are implemented and
verified incrementally after this design is approved. A protocol phase alone is
not Consumer completion. Existing baseline compiler failures remain failures.

## 2. Inspection and alternatives

The current broker owns one native TCP socket and permits one synchronous request
at a time. It already enforces correlation, framing, total exchange deadlines and
1 MiB request/response caps. The bounded writer/cursor and signed varints can be
reused. `message`, `header`, `nullable_bytes` and `endpoint` are reusable types.
The producer validator deliberately requires baseOffset=0, epoch=-1 and contiguous
record offsets: a Consumer must not reuse those restrictions on broker batches.

The native std surface has no proven thread/task scheduler. `std.process` process
execution functions are stubs. The repository has compression sources, but no
proven freestanding native std compression interface usable by this client.

Approaches considered:

1. Existing synchronous broker calls for every operation: smallest change, but a
   long JoinGroup/SyncGroup/Fetch can exceed poll deadlines or starve heartbeats.
   This does not satisfy the proposed reliable polling contract.
2. **Recommended: incremental Consumer-only I/O and cooperative scheduling.**
   Reuse native TCP and existing wire codecs. Keep requests pending across polls,
   service heartbeats between bounded I/O/decoding steps, and expose `service`
   while applications process a returned batch. No runtime/compiler extensions.
3. Background heartbeat threads/helper processes: permits long application pauses,
   but requires a new proven native concurrency/IPC and ownership model. It expands
   the frozen runtime/bootstrap scope substantially. Not proposed for this task.

Choice 2 and the restrictions below are proposals for user approval. This design
never promises background heartbeats while the application makes no library calls.

## 3. Declared compatibility scope

- Linux/amd64, PLAINTEXT, literal IPv4 bootstrap and advertised broker addresses.
- Kafka classic consumer group protocol, dynamic membership, eager Range assignment.
- Multiple explicit topic subscriptions and partitions; no regex subscription.
- RecordBatch magic 2, compression codec 0, CreateTime and LogAppendTime timestamps.
- Read-uncommitted visibility. Transactional data may be returned even if aborted;
  validated control records are never exposed as application records.
- No static membership, cooperative-sticky/RoundRobin assignment, KIP-848 consumer
  protocol, read-committed isolation, exactly-once semantics, TLS/SASL or DNS.
- Gzip/Snappy/LZ4/Zstd return explicit unsupported-codec errors with no offset
  advancement. Adding a codec requires native bounded decompression and separate
  correctness/bomb/CRC tests, not a library shell-out or silently skipped batch.

These limits must appear in public docs. "Production-quality" is claimed only
for the declared scope after all applicable acceptance tests pass.

## 4. Negotiated protocol baseline

Use ordinary request header v1 / response header v0, preserving the Producer's
non-flexible framing. Each opened connection negotiates ApiVersions v0 and
requires the selected versions for its role. No untested automatic version fallback.

| API | Key | Version | Purpose |
| --- | ---: | ---: | --- |
| ApiVersions | 18 | 0 | Existing negotiation |
| Metadata | 3 | 4 | Explicit topics, allow_auto_topic_creation=false, leader/broker discovery |
| FindCoordinator | 10 | 1 | Group coordinator discovery, coordinator type=group |
| JoinGroup | 11 | 2 | Dynamic classic membership, session/rebalance timeouts |
| SyncGroup | 14 | 1 | Leader distributes Range assignment |
| Heartbeat | 12 | 1 | Generation/member liveness |
| LeaveGroup | 13 | 1 | Graceful dynamic member departure |
| Fetch | 1 | 4 | Magic-2 records, bounded fetch bytes, isolation_level=0 |
| OffsetCommit | 8 | 2 | Generation/member fenced next-offset commits, retention=-1 |
| OffsetFetch | 9 | 2 | Explicit topic/partition committed offsets |
| ListOffsets | 2 | 1 | Earliest=-2 and latest=-1, timestamp lookup wire format |
| DescribeGroups | 15 | 1 | Bounded diagnostic view and membership acceptance evidence |

Pinned authority: Apache Kafka `3.9.1/clients/src/main/resources/common/message/`
request and response JSON schemas for each API. Implementers must read both sides
and preserve their version-specific throttle, nullable, array and error fields.
Do not derive response layouts solely from request versions.

References:
- https://github.com/apache/kafka/tree/3.9.1/clients/src/main/resources/common/message
- https://github.com/apache/kafka/blob/3.9.1/clients/src/main/java/org/apache/kafka/common/record/DefaultRecordBatch.java
- https://github.com/apache/kafka/blob/3.9.1/clients/src/main/java/org/apache/kafka/clients/consumer/RangeAssignor.java

## 5. Ownership, bounds and resumable I/O

Keep Producer APIs, `broker_send_request`, producer `validate_record_batch`, TCP
intrinsics and their limits unchanged. Add Consumer transport alongside them,
using `std.tcp.write_some/read_some` and the same frame/correlation rules.
Never share an owned socket with the synchronous Producer exchange functions.

Consumer owns at most four connections: bootstrap/metadata, coordinator RPC,
heartbeat to that coordinator, and current partition leader Fetch. Keep only one
leader socket and switch it when necessary; no socket arrays or accidental owner
copies. Endpoint metadata arrays contain addresses, not sockets. Reuse existing
broker connect/close/negotiation helpers where their synchronous call fits the
explicit operation deadline; all long-running group/fetch requests are incremental.

A pending exchange owns the request frame, write cursor, partial size header/body,
expected correlation, response size and absolute monotonic request deadline.
Correlation is consumed once when I/O begins. Handle partial writes/reads without
restarting a request. Peer EOF, malformed lengths/correlation and expired request
deadline close the connection. Poll's shorter caller deadline yields pending state
rather than discarding an otherwise valid JoinGroup/SyncGroup exchange.

Use short bounded TCP steps (at most 10 ms, further capped by remaining poll and
heartbeat deadlines); transient would-block/short-step timeout is pending work,
not failure of the total request. Verify actual intrinsic timeout behavior in
fault tests before relying on this rule. No infinite timeout or busy-spin loop.
Connect/reconnect and negotiation also respect their enclosing public-call budget;
negotiation is resumable when it cannot finish inside a poll's remaining budget.

Defaults/proposed hard caps:
- 1 MiB complete request and response frames, preserving the existing transport cap.
- Fetch byte budget 768 KiB, leaving response overhead headroom; Kafka may exceed
  requested bytes for a first batch. If the complete frame exceeds 1 MiB, return
  a bounds error and advance no offsets. Never truncate a frame to pretend success.
- 64 bootstrap brokers, 64 subscribed topics, 4096 discovered/assigned partitions,
  128 group members, 4096 buffered decoded records, 4096 headers per record.
- One outstanding delivered batch; at most 4096 records returned per poll, with
  a configurable smaller delivery count. Prefetched records stay within the same
  bounded queue. Over-limit responses fail explicitly without data/offset loss.

Decode/CRC work is resumable in bounded chunks, checking deadlines and servicing
heartbeats between chunks. A complete record set is validated before its records
or position changes become visible. No partially decoded/CRC-unverified delivery.
Peak retained Consumer memory is bounded by fixed connection frame buffers, one
validated record queue, metadata/assignment caps and bounded parser state. Clear
obsolete state on rebalance/close. Application-retained returned batches are the
application's memory responsibility; sustained-consumption tests release them.

## 6. RecordBatch and Fetch processing

Add a separate broker-record decoder; do not weaken producer validation.
Verify length, magic and CRC32C before trusting records. Parse nullable/binary
keys/values, UTF-8 header keys, duplicate headers and nullable values. Check all
integer additions, varint widths, count/byte limits and record boundaries.

Accept broker-assigned offsets/leader epochs and nontransactional/idempotent/
transactional producer metadata. Compacted batches can have gaps: record offset
deltas must increase and stay within lastOffsetDelta; they need not start at zero
or equal array indices. Count need not equal lastOffsetDelta+1. Header base/max
timestamps may refer to removed records. CreateTime uses checked base+delta;
LogAppendTime uses the broker batch timestamp. Empty/compacted/control batches
must advance fetch progress safely without inventing application records.

Fully validate control batches before suppressing them. Read-uncommitted data
visibility is explicit; do not claim aborted-transaction filtering. Reject reserved
attributes/unknown codecs rather than silently treating them as uncompressed.

Handle multiple complete batches per partition, requested offsets in the middle
of a batch, compaction gaps and replay after failure. Ignore records below the
requested offset only after validating the containing batch. Guard offset+1
and batch base+last-delta arithmetic against int64 overflow.

Kafka record sets may end in an incomplete trailing batch. This is distinct from
an incomplete TCP frame. Complete prior batches may be delivered only after
validation; a recognized bounded trailing partial batch is reported as such,
never emitted or committed, and the next Fetch resumes after the last complete
batch. Malformed minimum lengths, over-limit declarations or malformed complete
batches are errors. If no complete batch can be read, return an actionable
truncation/size error rather than endlessly returning empty success. Standalone
strict codec tests reject incomplete batches; Fetch-context tests cover legal
partial tails explicitly. No invalid CRC can be accepted as a partial-tail shortcut.

Poll fairly rotates assigned topic/partitions. Returned `consumed_record` includes
its topic and the existing `message` data (partition, offset, timestamp, key/value,
headers), avoiding the current message type's lack of a topic field.

## 7. Group state machine and heartbeat contract

States: New -> Discovering -> Joining -> Syncing -> RecoveringOffsets -> Stable;
recoverable failures enter Rediscovering/Rejoining/Backoff; terminal validation,
authorization, unsupported-version/codec or bounds failures enter Failed. Close
works from every state and is idempotent. Empty assignments remain healthy members.

Range leader assignment uses consumer subscription metadata version 0 and assignment
version 0. Sort member IDs and topic partition IDs deterministically; per topic,
consider only members subscribed to that topic and distribute contiguous ranges,
with remainder partitions going to earlier members. Validate incoming metadata,
member uniqueness, assignment ownership, duplicates and subscription membership.

Eager rebalance revokes all old assignments, invalidates delivery/ack tokens and
clears undelivered buffers before joining the new generation. Never commit or
deliver with a stale generation. New assignments recover committed positions
before new delivery. Metadata refresh handles partition-count/leader changes.

Default session timeout 10000 ms, heartbeat interval 3000 ms, request/rebalance
budgets validated against broker bounds. JoinGroup can remain pending across poll
calls. While group RPCs or Fetch wait, the scheduler services the dedicated
heartbeat connection whenever a valid member/generation needs liveness. Kafka's
pending-join rules are handled explicitly; no heartbeat is fabricated before a
valid generation exists. Broker rebalance timeout is independent of poll timeout.

**Cooperative contract:** the application must call `consumer_poll` or
`consumer_service` frequently enough for heartbeats (recommended service interval
<=1000 ms under defaults). The library has no background thread. A long processing
pause without either call can expire the session; on resumption the client fences
old delivery tokens and rejoins. Long-running application processing uses `service`
without implicitly acknowledging or committing the outstanding batch.

REBALANCE_IN_PROGRESS, ILLEGAL_GENERATION and UNKNOWN_MEMBER_ID stop delivery and
rejoin with proper member-ID handling. COORDINATOR_LOAD_IN_PROGRESS backs off;
COORDINATOR_NOT_AVAILABLE/NOT_COORDINATOR trigger discovery. Authentication/group/
topic authorization and incompatible group protocol failures are explicit terminal
errors. Preserve the Kafka native error code. Retry only bounded, identified
recoverable failures; expose the last error/retry state instead of hiding it.

Bootstrap/leader failure triggers metadata refresh and bounded reconnect/backoff.
Coordinator failure pauses delivery until membership is confirmed or re-established.
A lost generation invalidates outstanding batches. Read retries may duplicate
uncommitted records; no automatic skip or success claim on lost commit responses.

## 8. Delivered, processed and committed offsets

Track separately per partition: fetch-next, delivered-next, acknowledged/processed-
next and broker-confirmed committed-next. Fetching/prefetching is not processing.
Commit Kafka's next offset, never the last record's offset.

Require explicit `consumer_ack(delivery_id)` after the whole returned batch has
been processed. Only one batch may be outstanding; another data poll returns an
unacknowledged-batch error until ack, but `service` remains available. Tokens are
bound to the assignment epoch; stale or repeated acknowledgments fail safely.
Control-only progress becomes commit-eligible only after all earlier application
records are acknowledged. Do not commit ahead of queued/unprocessed records.

Manual commit snapshots acknowledged positions for current ownership and generation.
Automatic commit periodically sends only those same acknowledged positions; it
never assumes that returning a batch means the application processed it. This is
an intentional extension to the conceptual API to make at-least-once semantics
precise. Crash before commit may cause duplicates; no exactly-once guarantee.

After assignment, OffsetFetch recovers committed offsets. If no commit exists,
`initial_offset` chooses earliest (default) or latest via ListOffsets. Existing
out-of-range committed/fetch offsets produce an explicit error; no silent reset.
Expose offset inspection and explicit owned-partition seek for operator recovery;
seek invalidates pending delivery tokens/buffers and cannot automatically mark
skipped records processed. Commit state is updated only after broker confirmation;
per-partition commit errors remain visible even when some partitions succeeded.

Close attempts a final commit of acknowledged progress only when auto_commit is
configured, then LeaveGroup and all socket cleanup within a caller budget.
Return commit/leave failures visibly while still releasing every owned socket.
Manual-commit mode does not silently commit on close. Process termination without
a graceful close relies on session expiration and at-least-once replay.

## 9. Proposed public API

Use ordinary S structs, pointer borrows and `(value,error)` returns. Exact type
spelling may be settled in the implementation plan, without changing behavior:

```s
c, problem := std.kafka.consumer_new(config)
subscribe_error := std.kafka.consumer_subscribe(c*, topics)
batch, poll_error := std.kafka.consumer_poll(c*, 1000)
// Process batch.records, each with .topic and existing message in .data.
ack_error := std.kafka.consumer_ack(c*, batch.delivery_id)
commit_error := std.kafka.consumer_commit(c*, 5000)
close_error := std.kafka.consumer_close(c*, 5000)
```

Additional public operations: `consumer_service(c*,timeout_ms)` for heartbeat/
recovery without delivery or acknowledgment; current assignment/status; earliest/
latest and committed-offset inspection; explicit seek of a currently owned
partition; bounded DescribeGroups diagnostics. No direct copying of a live
Consumer or concurrent calls. No unbounded blocking waits.

`consumer_config` includes endpoint[] bootstrap, client_id, group_id, auto_commit
(default false), auto_commit_interval_ms (5000), initial_offset, session/heartbeat/
rebalance/request/connect budgets, max_poll_records and bounded fetch limits.
Validate all combinations before I/O. Empty poll due to the caller deadline is
an explicit timed_out/empty result, distinct from a transport request timeout.
State changes/errors must be observable. Never silently acknowledge a prior batch
merely because the application calls poll/service again.

## 10. File boundaries and incremental delivery

Keep Producer source/public behavior unchanged. Proposed new units under
`src/std/kafka/`: consumer_types, consumer_transport, consumer_protocol helpers,
metadata, fetch, decode, group_protocol, range_assignor, offsets, consumer (state
machine). Split group codecs further if needed to keep files reviewable. Shared
writer/cursor primitives may be reused; avoid broad refactors of working codecs.

Implementation sequence after approval:
1. Codec TDD for discovery/group/fetch/offset APIs, version negotiation and bounds.
2. Incremental Consumer exchange and resumable broker-record decoding; bounded
   deadlines, partial I/O and heartbeat interleaving proven with fault peers.
3. Real direct-assignment Fetch/native Producer roundtrip as an intermediate gate.
4. Full classic Range group lifecycle, two-process rebalance, liveness and recovery.
5. Acknowledgments/manual/auto commits, restart and at-least-once fault scenarios.
6. Full five-compiler acceptance, regressions, performance, fresh official bootstrap
   and required documentation. Intermediate gates are never final acceptance.

No unrelated compiler or frozen bootstrap input changes. If an actual required
S capability is unavailable, record the executable failure and revise the design
for review instead of quietly weakening the compiler or acceptance scope.

## 11. Acceptance and evidence plan

Use native S clients and the existing native Producer v3 against real Kafka 3.9.1.
No external Kafka client library in the Consumer. Official server admin commands
may create/describe topics and inspect group offsets as an independent oracle.

Run under Seed, canonical, stage2, stage3 and stage4 as separate labeled commands,
even if their canonical executable hashes match. Use native S subprocesses launched
by shell for concurrent consumers, coordinated with fresh local test directories.
Do not simulate rebalance with only a peer fixture.

Required real scenarios: metadata; two leaders/multiple partitions; exact binary/
null/empty keys, values, headers, timestamps and offsets; batch and middle-batch
fetch; group join/sync/heartbeat/leave; two consumers joining/leaving and disjoint
complete Range assignments; empty assignment; service liveness beyond a session;
intentional missed-service session loss/rejoin; manual commit/restart; auto commit
never passes unacknowledged records; crash before/after commit; full/partial commit
errors; stale ack/commit fencing; broker/coordinator shutdown and restart; leader
change; unknown topic/authorization/error paths where the fixture supports them.

Unit/fault scenarios: independent wire fixtures; every truncated prefix; malformed
lengths, counts, correlations and CRCs; overflow; compacted/control/log-append batches;
known unsupported codecs; over-limit frames/records; legal Fetch partial tails;
partial reads/writes; long pending JoinGroup over multiple short polls; heartbeat
interleaving; timeout/backoff; closed/default ownership and repeated close. No
malformed prefix or invalid CRC may change committed/processed state.

Before and after implementation, execute Producer, TCP and ApiVersions suites
including real broker acceptance. Run the full official regression recipe and
all unaffected checks after failures, retaining each status. Distinguish the eight
recorded baseline failures from new ones. Baseline failures remain reported failures.

After implementation run fresh Seed -> stage1 -> stage2 -> stage3 -> stage4 official
bootstrap in a new directory with a repository-local install prefix. Require exact
stage3/4 assembly and ELF equality and execution equivalence. Prior successful
bootstrap artifacts may supply compiler matrix inputs, not replace a fresh run.

Measure sustained and batch throughput, mean poll latency, producer-to-delivery
latency (wall clocks only for same-host timestamps; monotonic for durations), CPU
user/system time, peak RSS and RSS across repeated equal-size consumption windows.
Use released batches and fixed input/batch sizes; report retries/errors, sample
counts, warmup and compiler identity. Compare cold steady state with sustained
windows and single-record versus batches; optional official client baseline is a
test measurement only and not a product dependency. No invented numbers or claims
of no leaks from peak RSS alone.

Required final docs: `doc/kafka-consumer/{README,API,PROTOCOL,TESTING,RESULTS}.md`.
Record supported versions/limits, cooperative service/ack contract, recovery,
unsupported features, exact reproduction commands, every failure and benchmark
method/results. Results must distinguish implemented, executed, passed and incomplete.

## 12. Recorded pre-implementation state

HEAD: ac2c40aea9ab7c1a6403ef99185af2e7613d41ea. Producer changes are uncommitted;
the Consumer task must preserve them rather than resetting to HEAD.

Fresh snapshot/evidence:
`.bootstrap/kafka-broker/consumer-runs/design-20261115T054016Z/`.
It records HEAD, working-tree status/diff, tracked/untracked file hashes, compiler
copies, and hashes of 19,106 existing Phase 1 evidence files. Existing Java/Kafka
caches are reused via repository-local links; new cluster/log outputs are separate.

Fresh baseline statuses: Producer unit/fault native=0, Seed=0; existing broker
unit/TCP/ApiVersions faults native=0, Seed=0; real Kafka Producer native+Seed=0.
The real runner independently verified 11 produced records per compiler and also
ran its existing benchmarks. These are Producer measurements, not Consumer results.
`baseline-status.tsv` and per-suite logs hold actual exit results.

Recorded full regression baseline: 97/105 passed; these eight failed and were
reproduced on unchanged HEAD sources in the previous task:
1. test/stdlib-native/test_collections.py (Seed generic option type mismatch).
2. canonical_enum_mir_check.sh (Seed undeclared std at mir/program.s:1051).
3. canonical_aggregate_mir_check.sh (same).
4. canonical_cfg_mir_check.sh (same).
5. canonical_bitwise_mir_check.sh (same).
6. canonical_external_reachability_check.sh (same).
7. canonical_unit_shadow_production_check.sh (undefined identifier e).
8. canonical_statement_boundary_ast_check.sh (fixture does not return expected 42).

The seven shell checks are under test/native-bootstrap-diagnostic/. Full evidence
and the previous successful fresh four-stage bootstrap are described in
`doc/kafka-producer-phase1-report.md`; copied prior report/status evidence is in
this run. This design turn records that regression baseline, not a new full-suite
run. No Consumer API, group, offset, performance or bootstrap PASS is claimed.

## 13. Design review and preservation check

An independent native S/Kafka builder review reported "Nothing important left":
remaining details are implementation choices or explicitly gated feasibility checks.
This is a design review, not implementation/test approval. User approval of the
cooperative service contract, acknowledgment API and declared scope is still needed.

Fresh baseline runner exited 0. All five suite entries in baseline-status.tsv are
zero. All 19,106 prior Phase 1 evidence file hashes were rechecked with no changes;
all snapshotted pre-existing tracked/untracked source files also match their saved
hashes. compiler-sha256.json records Seed/canonical/stage2/stage3/stage4 identities.
The only new non-ignored source-tree artifact from this turn is this design doc.

Permission review for the first baseline command timed out before execution. A
single retry using a fixed script path succeeded; no test was skipped or reclassified.
