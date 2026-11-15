# Kafka capability matrix

Audit reports: [architecture](KAFKA_ARCHITECTURE.md) ·
[protocol coverage](KAFKA_PROTOCOL_COVERAGE.md) ·
[memory investigation](KAFKA_MEMORY_AUDIT.md) ·
[gap analysis](KAFKA_GAP_ANALYSIS.md) · [roadmap](KAFKA_ROADMAP.md).

Audited 2026-11-15. Scope and evidence root: [architecture](KAFKA_ARCHITECTURE.md).
PASS means verified within the stated scope, not a blanket production certification.
PARTIAL means implemented with missing behavior/qualification; FAIL means an
observed contract/test problem; BLOCKED means an environmental prerequisite prevented
execution; NOT IMPLEMENTED means no working implementation was found.
P0=release blocker, P1=high, P2=medium, P3=low, I=informational.
Source paths below are relative to `src/std/kafka/`. `E` is
`.bootstrap/kafka-audit/audit-20261115/`. Fresh evidence is distinguished from
retained historical results. The compiler/evidence section is generated from the
completed audit runs below.

## Producer

| Capability / status | Source and function | Behavior / evidence | Gap / severity / action |
| --- | --- | --- | --- |
| Open, version negotiation / PASS | `produce.s::producer_open`; `broker.s::broker_api_versions` | Requires advertised Produce v3; rejects unsupported versions; failed open closes socket. `test/kafka/producer-fault/{client,peer}.s`. | Fixed v3 only; I; document broker version qualification. |
| Single record / PASS | `produce.s::producer_publish` | Delegates to one-record batch. Real Producer test and independent official byte oracle. | No async API; I; preserve semantics. |
| Batch and magic-2 / PASS | `batch.s::encode_record_batch`; `produce.s::build_produce_request` | One topic/partition per request; 1..4096 records, atomic Kafka batch; no compression. `test/kafka/producer-unit/main.s`, `producer/main.s`. | 1 MiB entire unframed request, not 1 MiB values; P1 for large records; publish exact limits. |
| CRC32C / PASS | `protocol.s::crc32c`; `batch.s::validate_record_batch` | Castagnoli polynomial, payload from attributes onward. Fixed-wire vectors, truncation/valid-CRC structural mutation tests; independent broker consumption. | Bitwise CPU cost; P2; profile before optimizing. |
| Keys/values/headers / PASS | `batch.s::_k_record_bytes`, `encode_record_batch` | Binary/null/empty distinct, duplicate headers preserved; broker oracle covers 512 KiB values. | Producer accepts a malformed UTF-8 header key that its Consumer rejects; fresh `E/header-probe-*.log` codec roundtrip; P2/C-04; reject consistently. |
| Explicit partition / PASS | `produce.s::build_produce_request` | Caller partition serialized; returned identity checked. Message offset/partition ignored. | No key partitioner or automatic selection; P2; add only after routing. |
| ACK 0 / PASS (send-only) | `produce.s::producer_publish_batch`; `broker.s::_k_exchange` | Successful socket write, no response; offset=-1; acknowledged barrier in real test verifies ordered writes. | No acceptance/persistence proof, broker errors invisible; P1 use restriction; choose acknowledged mode where needed. |
| ACK 1 / PASS | Same functions | Waits for leader response; validates base offset. | No guarantee all replicas have acknowledged; I; choose durability policy deliberately. |
| ACK -1 / PASS | Same functions | Waits for current ISR according to broker policy. | ISR may shrink; cluster/topic min-insync-replicas matters; no fsync or exactly-once claim; I; qualify deployment settings. |
| Errors and timeout / PASS within scope | `broker.s::_k_remaining`, `_k_abort`; `produce.s::parse_produce_response` | Signed broker code preserved; valid broker error leaves connection open; malformed/correlation/transport errors close it. Fault peers cover EOF, timeout and negotiation. | No automatic broker retry classification/scheduling; P1; callers handle ambiguity. Serialization excluded from timeout. |
| Retry/recovery / NOT IMPLEMENTED | `produce.s::producer_publish_batch` | One exchange; failure returned, reopen explicitly. | No retry/backoff/dedup; P1; design with idempotence or documented at-least-once retry policy. |
| Leader discovery / NOT IMPLEMENTED in Producer | `produce.s::producer_open` | Requires supplied endpoint to lead selected partition; real wrong-leader error returned. | Consumer Metadata codec exists but not wired into Producer; P1; reuse only after reliability work. |
| Ordering / PARTIAL | `broker.s::_k_exchange`; sequential ownership | Sequential calls on same socket/partition; one batch has contiguous assigned offsets. | No cross-partition total order, retry reorder/dedup policy or failover order qualification; P2; test ambiguous outcomes. |
| Idempotence / NOT IMPLEMENTED | `batch.s::encode_record_batch` | ProducerId=-1, ProducerEpoch=-1, BaseSequence=-1. No InitProducerId state machine. | No partial idempotent mode despite v3 format; P1 if retry guarantees required. |
| Transactions / NOT IMPLEMENTED | `produce.s::build_produce_request` | TransactionalId=null; no transaction coordinator/API lifecycle. | Exactly-once unavailable; P2/defer until prerequisites. |

ACK semantics checked against the pinned
[Apache Produce schema](https://github.com/apache/kafka/blob/3.9.1/clients/src/main/resources/common/message/ProduceRequest.json).
They describe acknowledgment policy, not an unconditional durability guarantee.

## Consumer

| Capability / status | Source and function | Behavior / evidence | Gap / severity / action |
| --- | --- | --- | --- |
| Metadata and multiple bootstrap endpoints / PASS | `consumer.s::_kc_metadata_step`; `consumer_metadata.s::consumer_parse_metadata` | Cycles configured bootstrap entries on recovery, resolves leader IDs and coordinator. Real multi-broker fixtures. | Advertised DNS/IPv6 hosts cannot connect; P1 deployment restriction. |
| Fetch / PASS within bounded scope | `consumer_fetch.s::consumer_build_fetch`, `consumer_parse_fetch`; `consumer_poll.s::_kc_fetch_step` | v4, one partition, read-uncommitted, requested max<=768 KiB, 1 MiB response cap. | 1 MiB payload rejected; total decoded count<=4096; P1/C-03; document and redesign buffering/bounds as needed. |
| Record decoder / PASS within scope | `consumer_decode.s::consumer_decoder_step` | Broker offsets/epochs, CRC, CreateTime/LogAppendTime, gaps, delete horizon, binary/null/empty fields, UTF-8 header keys, validated control-marker suppression. Unit/real roundtrips. | Compressed records fail explicitly; read-committed unavailable. Malicious maximum CPU/GC pauses not fully qualified; P1. |
| Poll / PASS within scope | `consumer_poll.s::consumer_poll` | Bounded returned batch and one outstanding token; empty timed-out batch. Regular service/poll required. | max_poll_records does not bound decoded memory; P1/M-01. |
| ACK gate / PASS for serviced ownership | `consumer_ack.s::consumer_ack`, `consumer_commit_candidates` | Only matching current token/epoch changes processed progress; outstanding next delivery is excluded. Wrong/duplicate/stale-epoch unit cases. | ACK alone does not check expired session/max-poll clock; PARTIAL/P2/C-01. |
| Manual commit / PASS within scope | `consumer_offset_state.s::consumer_commit`, `_kc_begin_commit`; `consumer_ack.s::consumer_apply_commit` | Snapshots processed offsets, fences epoch/generation, confirms only successful partition responses. Fault peers verify lost/timeout/partial/auth. | Lost response outcome unknown; no exactly-once; P1 application contract. |
| Automatic commit / PASS within scope | `consumer_offset_state.s::_kc_commit_step`; `consumer.s::consumer_close` | Uses same ACK gate during poll/service; close may commit already-ACKed progress when enabled. | Not timer-driven without service, not implicit processing ACK; I; explain clearly. |
| Offset restoration / PASS | `consumer_offset_state.s::_kc_initial_offsets` | OffsetFetch v2, then ListOffsets v1 earliest/latest if missing; real restart/replay cases. | No automatic out-of-range reset policy; P2; explicit error + seek. |
| Seek / PASS within documented ownership | `consumer_poll.s::consumer_seek` | Invalidates deliveries/queue/decoder/epoch, rewinds other partitions to processed progress, target marked not processed. | No timestamp-seek high-level API; P3; retain explicit offset contract. |
| Heartbeats / PASS with cooperative service | `consumer.s::_kc_heartbeat_step`, `_kc_service_once` | Separate role socket and service interleaving; tested beyond session and during processing. | No background liveness; P1 application integration requirement. |
| Session/max-poll / PASS via service/poll checks | `consumer.s::consumer_check_liveness`; `consumer_poll.s::consumer_poll` | Revokes assignment/token and rejoins after expiry; max-poll checked before refresh. | ACK direct-call clock gap C-01; P2. |
| Range assignment / PASS | `consumer_assign.s::consumer_range_assign` | Sorted per-topic eager Range, heterogeneous subscriptions, empty assignments; real concurrent disjoint/complete sets. | <=128 members, <=64 topics, <=4096 partitions; no scale qualification at ceilings; P1. |
| Rebalance and generation fencing / PASS within tested cases | `consumer.s::_kc_revoke`, `_kc_group_step`; `consumer_ack.s::consumer_apply_commit` | Eager revoke, epoch changes, broker generation/member commits; real tests distinguish stale-generation broker response from local fencing. | No cooperative/static/KIP-848 membership or rebalance callbacks; P2. |
| LeaveGroup / PARTIAL | `consumer.s::consumer_close` | Reconnects lost group socket, reports Leave error, closes sockets, repeat-safe. | Remote-idle group socket close fails rather than reconnecting: fresh real Seed/canonical probe, P1/R-02. Managed decoder/snapshot references also retained, P2/M-02. |
| Coordinator/leader recovery / PARTIAL | `consumer.s::_kc_recover`, `_kc_metadata_step`; `consumer_offset_state.s::_kc_commit_step` | Retry selected transport/coordinator/generation/leader errors; 100ms retry, metadata/rejoin; real outage and edge tests. | Not all retriable Kafka codes handled; failover follow-up ISR restoration may fail in fixture; P1 reliability qualification. |
| Dynamic partitions / PASS within scope | `consumer.s::_kc_metadata_step`; `consumer_metadata.s::consumer_metadata_changed` | 30-second subscribed metadata refresh; changes revoke/rejoin; real growth test. | No instant topology notification, regex subscription or incremental assignment; P2. |
| Memory / FAIL for Seed sustained suitability; PARTIAL canonical | Runtime paths in architecture; `consumer_transport.s`, `consumer_decode.s`, `consumer_poll.s` | Fresh size sweep and 30-minute run in memory report. | No universal bounded-RSS guarantee; P0 production gate; fix before advanced features. |

## Four offset positions

For each assigned partition, `topic_partition.offset` is the next Fetch position.
The last delivery's end position is `outstanding_end_offset`, paired with token and
epoch; it is not commit-eligible on delivery. `processed_offset` with
`processed_valid=true` is ACKed progress. `committed_offset` changes only after a
successful matching broker response. `_kc_begin_commit` copies only processed-valid
candidates; `consumer_apply_commit` uses the captured snapshot, not later delivery
or Fetch progress. Compaction gaps/control-only validated ranges can advance safe
progress without an application record ACK. That is distinct from acknowledging
an unprocessed application record. Seek intentionally resets the target position.

Source audit and supplied offset/fault tests found no ordinary path that promotes
a delivered-but-unacknowledged application record into a commit snapshot. This is
bounded evidence, not a proof over arbitrary public-struct mutations or all faults.
Applications can mutate exposed state; they must treat internal fields as read-only.

## Fresh execution and compiler compatibility ledger

All commands ran from `/root/shuwen/s` on 2026-11-15. Loopback execution required
socket-enabled tool execution: the initial sandboxed attempt was **BLOCKED** with
`java.net.SocketException: Operation not permitted`, preserved in
`E/acceptance.log` (exit 1). No Java installation was performed; existing repository
Corretto 17.0.21 and the checksum-verified Kafka 3.9.1 distribution were reused.

The next stock runner attempt was **FAIL** at `consumer-benchmark/payload_sim.s`
with duplicate `main.main` (exit 1, `E/acceptance-local.log`). A retained audit copy
of the builder selects `test/kafka/consumer-benchmark/main.s` instead of its glob;
the copied acceptance runner uses this builder and an explicit repository root.
No test assertions or production sources were changed. This is a qualified audit
run, not a claim that the unchanged stock command passes.

| Compiler path | Compiler SHA256 | Build + run evidence | Fresh status |
| --- | --- | --- | --- |
| seed: `bin/s_seed` | `f677296274cc4d586bcc8eecf939a01b2a478fe311d2ab2ac5556a053bb49c37` | `E/acceptance-isolated/seed/build-*.log`, executables and logs; 39/39 status rows exit 0 | PASS |
| canonical: `bin/s_compiler` | `783cedef0da1cca00330f51a23646846f518649d287d227f876e812eabad4e73` | `E/acceptance-isolated/canonical/build-*.log`, executables and logs; 39/39 status rows exit 0 | PASS |
| stage2: `.bootstrap/kafka-broker/phase1/selfhost/stage2` | `783cedef0da1cca00330f51a23646846f518649d287d227f876e812eabad4e73` | `E/acceptance-isolated/stage2/build-*.log`, executables and logs; 39/39 status rows exit 0 | PASS |
| stage3: `.bootstrap/kafka-broker/phase1/selfhost/stage3` | `783cedef0da1cca00330f51a23646846f518649d287d227f876e812eabad4e73` | `E/acceptance-isolated/stage3/build-*.log`, executables and logs; 39/39 status rows exit 0 | PASS |
| stage4: `.bootstrap/kafka-broker/phase1/selfhost/stage4` | `783cedef0da1cca00330f51a23646846f518649d287d227f876e812eabad4e73` | `E/acceptance-isolated/stage4/build-*.log`, executables and logs; 39/39 status rows exit 0 | PASS |

39 rows per path include eight build checks and 31 executable/scenario/measurement
checks. Each path was invoked independently on the current Kafka sources;
canonical and Stage2/3/4 are byte-identical compiler binaries, so these are five
execution paths, not five independent code generators. No requested stage was
unavailable. Compiler file identities are also recorded by `file` in
`E/identity-*.txt`. Fresh Kafka builds are not fresh compiler-bootstrap convergence.
A full compiler regression recipe was not rerun in this audit; the previously
reported eight baseline failures are not silently reclassified.

| Suite | Command / evidence | Result |
| --- | --- | --- |
| Consumer full matrix | `bash E/acceptance-audit.sh E/acceptance-isolated`; `acceptance-isolated.exit`, `status.tsv`, per-label logs/binaries and source-integrity checks | PASS; process exit 0; 195/195 status rows exit 0 |
| Commit response faults | `bash misc/scripts/check-kafka-consumer-commit-faults.sh E/commit-fault`; `E/commit-fault/status.tsv` | PASS; all 20 cases exit 0 (lost response/timeout/partial/auth × five paths); native peer fixtures, not real ACL broker tests |
| Real edge scenarios | `bash misc/scripts/check-kafka-consumer-edge.sh E/edge`; `E/edge.exit`, `status.tsv` | PASS; five paths × nine recorded checks; intentional SIGKILL checks exit 137, other checks exit 0 |
| Producer unit/fault and broker unit/TCP faults | `bash E/check-kafka-{producer,broker}-faults.sh COMPILER LABEL`; `E/regression-status.tsv`, per-suite logs | PASS under Seed and canonical, each suite exit 0; controlled native peers |
| Producer real + official consumer oracle | `bash E/check-kafka-producer-real.sh`; `E/producer-real.log`, `E/producer-real/oracle-{native,seed}.log` and exact consumed byte files | PASS Seed/canonical; independent oracle checks 11 records per path, plus benchmarks |
| Broker ApiVersions real | `bash E/check-kafka-broker-real.sh COMPILER LABEL`; `E/broker-real-{seed,canonical}.log` | PASS under both compilers; suite exit 0 |
| Malformed header codec roundtrip | `bash E/header-probe-run.sh`; `E/header-probe-status.tsv`, `header-probe-{seed,canonical}.log` | PASS as a reproduction: Producer encode/validate return 0, Consumer returns protocol error 3; no real broker claim |
| Internal behavior probes | `bash E/probe-run.sh`; `E/probe-status.tsv`, `probe-*.log` and executables | PASS as reproductions under all five paths; observed behaviors are findings, not fixes |
| Remote-idle close follow-up | `bash E/idle-close-run.sh`; `E/idle-close-status.tsv`, detailed client/broker logs | FAIL under Seed and canonical: close code 4/native 104, client exit 8 after stable membership; controlled real broker idle setting 5000ms |
| RSS size sweep | `bash E/memory-run.sh`; `E/memory-status.tsv`, per-process `/proc` samples and logs | PARTIAL: 30-minute consumption completed, but final close failed (child exit 13); 1 MiB rejection is unsupported behavior, not successful consumption |

Copied Producer/broker runners change only output directories and repository-root
resolution, so existing historical evidence paths are not overwritten. Their exact
text is retained in E, along with `regression-run.sh` that serializes shared fault
and broker ports. Current source hashes are in `E/source.sha256`; final
verification checks those against disk. The initial diagnostic parser/void-tail
compiler failures are transcribed in `E/harness-build-attempts.md` (the harness
reused its build-log paths); run-level attempt logs remain. They are not called
Kafka implementation test failures. The implementation code was not changed to make probes pass.

The edge runner retries broker ISR restoration using assertions; intermediate
`AssertionError` lines in its logs are not individual PASS claims. Its final exit,
all scenario rows and successful broker restoration govern the suite result.
Neither successful edge checks nor peer fixtures prove real ACL behavior.

## Measured performance (finite backlog workload)

| Compiler | Single-delivery records/s | Batch-delivery records/s | Single mean poll ms | Batch mean poll ms | Peak native RSS single / batch MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| seed | 582 | 594 | 1.700 | 107.290 | 449.4 / 498.8 |
| canonical | 1847 | 1881 | 0.539 | 33.992 | 40.3 / 40.1 |
| stage2 | 1845 | 1879 | 0.540 | 34.042 | 40.6 / 40.0 |
| stage3 | 1831 | 1838 | 0.544 | 34.776 | 39.0 / 40.0 |
| stage4 | 1848 | 1843 | 0.539 | 34.701 | 40.0 / 40.0 |

Method: 8,192 records × 256-byte values, one topic/partition, Producer preload in
64-record ACK=1 batches, requested Fetch max=16 KiB, application delivery limit
1 or 128 (actual native record batches contain 64). Production finishes before
the timed drain. Same native process includes Producer allocations; process RSS
is sampled every 20 ms by the repository measure.py, with GNU time family
resources separately. No warmup; other audit jobs share the host. Larger batch
poll latency reflects more records/work per call and is not per-record latency.
End-to-end latency includes preload/backlog residence. These are not steady-state,
maximum sustainable throughput, CPU-isolated results, a multi-partition scale
claim, or a matched external-client comparison. Resource files and samples retain
CPU seconds, wall time and window memory for reanalysis.
