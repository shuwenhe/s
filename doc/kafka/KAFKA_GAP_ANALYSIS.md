# Kafka gap analysis and deployment assessment

Audit: 2026-11-15. Evidence root `E`, status definitions and source map are in
[KAFKA_CAPABILITY_MATRIX.md](KAFKA_CAPABILITY_MATRIX.md) and
[KAFKA_ARCHITECTURE.md](KAFKA_ARCHITECTURE.md). These findings describe the current
checkout, including its preexisting uncommitted Kafka code. Audit diagnostics do
not alter the native implementation.

## Prioritized findings

| ID / status / severity | Evidence, source and function | Current behavior | Missing behavior | Recommended action |
| --- | --- | --- | --- | --- |
| M-01 / FAIL for Seed deployment gate; PARTIAL canonical / P0 | `E/memory-524288-{seed,canonical}/samples.json`; `src/runtime/selfhost_linux_amd64.S::s_alloc`; `standalone_amd64_backend.c::standalone_analyze_regions`; `consumer_transport.s::_kc_body_append`; `tcp.s::_bytes` | 16 repeated 512 KiB deliveries peak at 720,932 KiB Seed vs 49,096 KiB canonical; Seed remains 720,932 KiB after reset/idle. Mutable effectful path has no general Seed tracing collector. | Bounded process RSS under sustained actual workloads for all deployment compilers. | Establish per-compiler allocation/lifetime budgets, isolate transport/decoder/state allocation; choose ownership/reuse/collection design, then sustained regression. Do not assume clearing an S field frees memory. |
| M-02 / FAIL cleanup completeness / P2 | `consumer.s::_kc_revoke`, `consumer_close`; `E/probe-{seed,canonical,stage2,stage3,stage4}.log` | Close clears links, assignment and queue but retains `decoder`, `commit_snapshot`, metadata/join/config fields; probe retains 65,536 decoder bytes and one snapshot entry after close. Revocation also does not reset decoder. | Prompt release of stale managed references during mid-decode close/rebalance. | Explicitly clear lifecycle-owned transient fields; test real mid-fragment/mid-CRC/mid-decode revocation and retained-object reachability. Retention is bounded per object and does not alone explain all observed growth. |
| C-01 / PARTIAL local expiry fencing / P2 | `consumer_ack.s::consumer_ack`; `consumer.s::consumer_check_liveness`; `E/probe-*.log` | ACK returns success and advances processed position after simulated expired session if no service ran; later liveness check revokes. Poll with an outstanding token returns unacknowledged before its liveness check. | Immediate clock-based ACK rejection without requiring an intervening service. | Check local liveness at ACK entry and qualify token behavior after session/max-poll lapse. This probe does not demonstrate a stale broker commit: commit service checks ownership and broker generation still fences it. |
| C-02 / NOT IMPLEMENTED Producer recovery / P1 | `produce.s::producer_open`, `producer_publish_batch`; real wrong-leader/unknown-topic test | Supplied endpoint/partition, one sequential request, no retry or deduplication. | Automated Metadata routing and recovery with explicit ambiguous-outcome policy. | Keep callers responsible today; build routing only after memory gates and design retry/idempotence together. |
| C-03 / PARTIAL bounded record compatibility / P1 | `consumer_types.s::consumer_new`; `consumer_decode.s::consumer_decoder_step`; `consumer_transport.s::consumer_exchange_step`; `E/probe-*.log`, `memory-1048576-*/stdout.log` | 4,160 valid records in 37,248 bytes fail total decoded count cap; 1 MiB value fails full-frame cap before decoding. Bounds errors become terminal. | Ability to consume arbitrary ordinary broker batches and window large responses without whole-response output accumulation. | Publish exact limits; add independent broker tests around record-count/frame boundaries; design bounded decode windows without dropping unACKed data. Do not merely raise caps. |
| C-04 / PARTIAL header interoperability / P2 | `batch.s::encode_record_batch` vs `consumer_decode.s::_kc_header_utf8` | Producer writes arbitrary string bytes as header names; Consumer rejects malformed UTF-8 names. | Consistent public validation rules and regression proving native Producer output is consumable by native Consumer for accepted inputs. | Reject invalid UTF-8 before send or specify encoding contract; retain binary header values. `E/header-probe-{seed,canonical}.log` reproduces encode/Producer-validation success and Consumer rejection. This is a codec roundtrip, not a real invalid-name broker roundtrip. |
| R-01 / PARTIAL recovery/error classification / P1 | `consumer.s::_kc_recover`; `consumer_ack.s::_kc_offset_error_rank`; `consumer_offset_state.s::_kc_commit_step`; real edge logs | Selected transport/coordinator/generation/leader errors retry; other errors become terminal, with specialized commit handling. | Exhaustive API-specific retriable/authorization/fencing matrix; bounded retry policy and partition-loss/truncation qualification. | Enumerate against pinned Kafka errors, test each state transition, distinguish peer acceptance from real ACL/failover behavior. |
| R-02 / FAIL remote-idle close recovery / P1 | `consumer.s::consumer_close`, `_kc_link_ready`; `E/idle-close-{seed,canonical}.log`, `idle-close-status.tsv`; `E/memory-sustained/samples.json` | Real broker with connections.max.idle.ms=5000 closes idle group socket while separate heartbeats keep membership stable. Both compilers return close_code=4/native=104 (read/EOF), client exit 8. Long run separately exits 13 on close after 2332 deliveries. | Reconnect-and-retry Leave when remote closure is discovered during close; current reconnect only handles a locally known closed/pending socket. | Add bounded reconnect on eligible transport failure, retain original errors/ownership safety and regression. Idle closure is a supported explanation for the long failure, not proof of its unlogged exact error. |
| S-01 / NOT IMPLEMENTED authenticated/encrypted Kafka / P1 deployment-dependent | Kafka links call `std.tcp`, never `std.tls`; no Kafka SASL handshake/authentication state | PLAINTEXT only. Existing repository TLS bridge and crypto primitives are separate. | TLS trust/identity verification and SASL credentials/mechanisms. | Gate external deployment requiring authentication; integrate TLS transport first, then SASL. Do not silently change native linkage model. |
| S-02 / NOT IMPLEMENTED endpoint portability / P1 deployment-dependent | `src/std/tcp.s::_address`, `dial_ipv4`; Consumer metadata host pass-through | Literal IPv4 only, including advertised broker/coordinator addresses. | DNS, IPv6, refresh/address failover. | Test endpoint contract explicitly; implement bounded resolver lifecycle and IPv6 socket support after reliability. |
| P-01 / PARTIAL scalability/performance / P1 | `consumer_poll.s::_kc_fetch_step`; `consumer_assign.s::consumer_range_assign`; codegen array copying; fresh benchmark logs | One active Fetch partition, round-robin, synchronous role connects; array appends/updates allocate/copy; bitwise CRC. Benchmark is finite 2 MiB preload/drain on shared host. | Partition/broker/member scaling, fairness, concurrent steady-state p95/p99 latency, sustainable throughput and memory plateau. | Publish measured workload, profile before optimization; measure 1/16/128+ partitions and heterogeneous traffic after memory fixes. |
| T-01 / FAIL stock test entrypoint / P1 | `misc/scripts/build-kafka-broker-test.sh`, consumer-benchmark case; `E/acceptance-local.log` | Glob includes `main.s` and preexisting `payload_sim.s`, both define main; stock acceptance exits 1. | Reproducible stock acceptance command on this checkout. | Select explicit entrypoint or isolate simulator in separate test mode. Audit uses retained copied builder/runner, changes documented; no implementation/test weakening. |
| T-02 / PARTIAL compiler qualification / P1 | Fresh `E/acceptance-isolated/*/compiler.sha256`, build logs and status.tsv; probe identity logs | All five requested paths are present and separately invoked. Canonical and Stage2/3/4 hashes are identical. | Fresh bootstrap provenance/convergence from current source; full compiler regression rerun outside Kafka. | Do not treat equivalent binary labels as independent code generators; retain independent invocation evidence and run broader compiler/bootstrap gates before release. |
| D-01 / FAIL pre-audit documentation consistency; corrected / P2 | Prior main README claimed Fetch/Consumer unsupported; Consumer README said in progress; RESULTS listed running attempts despite later retained results | Documentation lagged actual source and historical artifacts. | Single current scope/evidence summary without erasing prior failed attempts. | Updated entry docs point to this audit; retain historical results and distinguish fresh audit evidence. |

## Evidence limitations and untested edges

The synthetic probes exercise internal functions and deliberately constructed
state. They establish the stated local behavior, not a broker exploit. The memory
size sweep uses separate official Java production so Producer allocation is absent
from measured native RSS. It replays one retained record with seek/ACK/commit and
one deliberate session lapse; it is not an unbounded stream of newly appended data.
The full acceptance benchmark includes native Producer preload and must not be
presented as Consumer-only memory. See the memory report for measured checkpoints,
long-run methodology and remaining limitations.

Missing high-value coverage includes: mid-decode rebalance/close with a live large
Fetch, repeated poisoned large/compressed batches, real ACL permission loss after
join, broker-side authorization combinations, quota behavior, log truncation,
leader/coordinator migration while OffsetCommit is in flight, metadata endpoint
changes, malformed maximum-count group assignments, many hot/cold partitions,
long application processing near all deadlines, and multiple Consumers in one
process. Existing edge/fault scenarios cover selected examples, not every ordering.

## Final recommendation

1. **Production-oriented today:** explicit acknowledged native Produce, bounded
   uncompressed magic-2 decoding, classic Range membership, cooperative heartbeats,
   separate delivery/ACK/confirmed commit positions and explicit errors. These
   are useful foundations for controlled Kafka 3.9.1, Linux/amd64, IPv4/plaintext
   integrations with application supervision and known record limits.
2. **Incomplete:** sustained memory qualification across allocators, general
   record/partition scalability, Producer routing/retry/idempotence, security,
   endpoint portability and modern group/transaction features.
3. **Highest risk:** Seed process-lifetime allocation growth, failed sustained close gate and unqualified
   workload memory bounds. Large-response/record-count terminal limits and caller
   liveness integration follow. Local ACK clock checking and cleanup references
   are reproducible smaller correctness/lifecycle gaps.
4. **Production blockers:** no general bounded-memory/service-level guarantee;
   environments needing TLS/SASL or DNS cannot use this client as implemented;
   stock acceptance command currently fails without the documented audit entrypoint
   selection. Current evidence is one Kafka version and identical later-stage
   compiler binaries, not a release certification.
5. **Next:** fix allocation/lifetime correctness and cleanup, make the stock
   acceptance path reproducible, add memory/record-boundary reliability gates,
   then profile and qualify actual deployment workloads. Security comes next
   when required; routing/error recovery should precede automatic Producer retries.
6. **Defer:** transactions/exactly-once, cooperative/static/new-protocol groups,
   general pooling, flexible API expansion and broad codec work until memory and
   reliability gates pass. Compression may be advanced if an immediate broker
   interoperability requirement justifies it, with decompression bounds first.
