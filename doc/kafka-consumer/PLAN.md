# Native Kafka Consumer v1 Implementation Plan

> Execution: superpowers:executing-plans; test-driven, inline. User approved DESIGN.md and explicitly authorized immediate implementation without another approval.

Goal: Native S Consumer v1 against Kafka 3.9.1 with incremental I/O, classic Range groups, cooperative heartbeat/service, explicit ACK-gated commits and verifiable acceptance.
Architecture: Consumer-only connection state machines reuse existing TCP and wire primitives. Producer code/semantics remain intact. Record decoding supports broker-assigned and compacted/control magic-2 batches without weakening the producer validator.
Tech: S, standalone Seed/canonical/stage2/stage3/stage4, repository-local Kafka/Java test server.
Spec: doc/kafka-consumer/DESIGN.md plus authorized execution request saved with the run evidence.

## Global constraints

Existing checkout only; no destructive git operations, unrelated compiler/runtime changes, threads, Java/C/C++ client dependencies or overwriting historical Producer evidence. Use fresh evidence directories. No later phase before targeted prior-phase tests pass. Preserve eight recorded baseline failures as failures.

## Review focus

1. Truncated/corrupt/compacted/control batches and unsupported compression cannot advance delivered/processed/committed offsets (Tasks 1/2).
2. Short poll deadlines cannot restart or discard pending group requests; heartbeat deadlines must survive partial I/O (Tasks 1/3).
3. Revocation/session loss/seek invalidate ACK tokens; commits never cross unacknowledged gaps (Tasks 3/4).
4. Coordinator/leader changes and lost commit responses retain retryable state and never claim a commit succeeded (Tasks 2/4).
5. Bounded queues and caps remain enforced through retries, rebalance and sustained consumption (Tasks 1/5).

## Task 1 — Phase 1 metadata, incremental exchange, batch decoding and Fetch

Files: src/std/kafka/consumer_transport.s, consumer_decode.s, consumer_metadata.s, consumer_fetch.s; test/kafka/consumer-unit/*.s, consumer-fault/*.s, consumer-phase1/*.s; misc/scripts/check-kafka-consumer-*.sh; extend standalone builder modes.
Interfaces: consumer_link with owned broker plus pending frame/correlation/deadline state; consumer_exchange_begin(link*,request,timeout_ms) error; consumer_exchange_step(link*,slice_ms) error; decode_record_batches(data,partition,requested_offset) (decoded_records,error); build/parse Metadata v4 and Fetch v4; topic_partition with topic/id/leader/offset state.
- [x] Add independent fixed batch and malformed-prefix/CRC/compression tests; run RED.
- [x] Implement bounded broker batch decoder with offset/timestamp arithmetic, gaps, control filtering, nullable/binary fields and headers; run GREEN under Seed/canonical.
- [x] Add incremental framing/partial I/O/deadline/correlation tests; run RED, implement, run GREEN.
- [x] Add Metadata/Fetch wire and real Producer-to-Fetch exact-field tests; run RED, implement v4, run GREEN.
- [x] Record Phase 1 evidence and perform read-only review before proceeding.

## Task 2 — Phase 2 classic group codecs and Range assignment

Files: consumer_group_protocol.s, consumer_assign.s, consumer_types.s, consumer.s; test/kafka/consumer-group/*.s and unit fixtures.
Interfaces: consumer_new(config) (consumer,error), consumer_subscribe(consumer*,string[]) error, consumer_poll(consumer*,timeout_ms) (consumer_batch,error); bounded FindCoordinator v1, JoinGroup v2, SyncGroup v1 and consumer protocol v0 payloads; range_assign(member subscriptions,metadata) (assignments,error).
- [x] RED/GREEN wire fixtures, deterministic per-topic Range assignment, empty and heterogeneous subscriptions, duplicate/member/partition bounds.
- [x] Implement member/generation/discovery/join/sync states with pending exchanges across polls.
- [x] Verify real two-consumer, multiple-topic/partition membership and complete disjoint assignments; record phase results.

## Task 3 — Phase 3 cooperative heartbeats, rebalance and LeaveGroup

Files: consumer.s, consumer_group_protocol.s; heartbeat/fault/group scenarios.
Interfaces: consumer_service(consumer*,timeout_ms) error, consumer_status/assignment inspection, consumer_close(consumer*,timeout_ms) error; Heartbeat/LeaveGroup v1. Four separate single-owner connection roles (bootstrap, group RPC, heartbeat, Fetch).
- [x] RED/GREEN heartbeat interleaving with long pending requests, session expiry, max-poll interval and token revocation fixtures.
- [x] Implement monotonic scheduling, bounded service slices, eager revoke/rejoin, coordinator/leader rediscovery and explicit recovery/error status.
- [x] Real tests: join/leave rebalance, >session service liveness, delayed application processing, missed-service loss, shutdown/restart recovery and idempotent close. Record evidence.

## Task 4 — Phase 4 ACK and offsets

Files: consumer_offsets.s, consumer.s, consumer_types.s; offset/ACK unit and integration tests.
Interfaces: consumer_ack(consumer*,delivery_id) error; consumer_commit(consumer*,timeout_ms) error; consumer_seek(...); OffsetCommit v2, OffsetFetch v2, ListOffsets v1, DescribeGroups v1 diagnostic helper.
- [x] RED/GREEN explicit one-outstanding-batch tokens and contiguous per-partition processed progress, no implicit ACK, stale ACK/commit rejection, partial commit failure state.
- [x] Implement manual/automatic commit of acknowledged positions only; earliest/latest initial offsets and explicit out-of-range errors; commit response confirmation and retry snapshots.
- [x] Real manual/auto commit, restart recovery, unacked crash replay, lost response, revoked partition and graceful shutdown tests. Record phase results.

## Task 5 — Phases 5/6 comprehensive acceptance, measurements and docs

Files: acceptance scripts, matrix/scenario S tests, doc/kafka-consumer/{README,API,PROTOCOL,TESTING,RESULTS}.md.
- [ ] Run all 21 requested real/fault scenarios under five labeled compiler paths; retain command/exit/log/identity evidence.
- [ ] Re-run Producer and TCP/ApiVersions in fresh snapshots/directories preserving old evidence.
- [ ] Full compiler recipe: execute every check even after failures, compare eight baseline failures, retain environments separately.
- [ ] Fresh official four-stage bootstrap with local install prefix; compare stage3/4 assembly and ELF and run execution equivalence/source integrity.
- [ ] Measure throughput, batch/poll/end-to-end latency, CPU, peak RSS and sustained windows without invented results.
- [ ] Independent whole-change review; fix material findings with regressions; finalize supported-version/API/limitations/reproduction/results docs.

## Ledger / rulings

- Work inline in existing requested main2 checkout. Preserve uncommitted Producer changes; no automatic commits or worktree creation. Backup, initial status/HEAD and historical evidence hashes live under the unique consumer implementation run referenced by .bootstrap/kafka-broker/consumer-current-impl-run.txt.
- Before implementation, reuse the fresh design-turn baseline only after verifying unchanged Producer source hashes; it passed both compilers' Producer and broker faults and real Kafka. The eight baseline regressions and prior bootstrap evidence are recorded, not reclassified.
- Pre-flight interfaces: Tasks 2/3/4 consume Task 1 link and record structures; group RPCs remain resumable, heartbeat has its own link, ACK tokens are distinct from fetch progress. No interface conflict identified.
- Max poll interval is an additional explicit config/liveness constraint requested in execution prompt; enforce independently of session timeout and service-based heartbeats.

Phase 1: targeted unit/fault/real acceptance PASS under Seed and canonical, attempt2 exit0; all three independent review findings corrected with regression tests. Evidence doc/kafka-consumer/RESULTS.md.
Ruling for Phase 2: introduce the minimum Heartbeat error probe needed to observe a group rebalance while exercising simultaneous consumers; full scheduling, session/max-poll and recovery acceptance remains Phase 3. Kafka membership cannot discover a new-member rebalance from Fetch, which is group-agnostic. This adds no architectural change and avoids a fake two-member test.

Phase 2: targeted unit and real single/multi-member Range groups PASS under both compilers; attempt2 exit0. Attempt1 Seed fail retained and corrected by avoiding tuple reassignment. No group completion claim beyond current phase; Phase3/4 remain pending.

Phase 2 independent review: no material findings. Phase3 begins only after Phase2 attempt2 exit0 and review.

Phase3 PASS: attempt3 exit0 Seed/canonical unit + real liveness >session, lapse/rejoin, maxpoll, real pair rebalance, graceful Leave including forced group-socket-loss reconnect. Review P2 corrected, reviewer confirms resolved. Phase4 may begin.

Phase4 targeted PASS: attempt2 exit0 under Seed/canonical; ACK/manual/auto/restart/replay/seek. Review mixed-status priority and closed-connection retry corrected with RED92/93 to GREEN, reviewer verified fixes. DescribeGroups diagnostic codec remains implementation work before final acceptance; Phase5/6 tests/measurements/docs/bootstrap pending.

Final review corrections: check prior poll timestamp before updating it; reset
soft coordinator recovery on full revocation; refresh subscribed metadata every
30 seconds and rejoin on topology change; reject non-UTF-8 header names. Fresh
Seed/canonical targeted units passed. Real Seed growth/processing/recovery passed
in matrix attempt3; large-Fetch performance test failed and remains recorded.
Commit-response loss/timeout/partial/authorization native fixtures are in progress.
Full compiler regressions: 97/105 PASS, same eight baseline FAIL; no reclassification.
