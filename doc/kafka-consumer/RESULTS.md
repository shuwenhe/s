# Current capability audit — 2026-11-15

Fresh evidence is under `.bootstrap/kafka-audit/audit-20261115/`. The five-path
Consumer acceptance matrix passed (39 recorded checks per path), as did all 20
native commit-fault cases, the real crash/fencing/failover matrix, Producer real
acceptance under Seed/canonical with the official byte oracle, and broker/Producer
fault and broker-real regressions. The stock acceptance attempt failed on duplicate
benchmark main definitions; the successful audit runner explicitly selects the
intended benchmark main and preserves the original failed logs.

The memory sweep and sustained measurements, including compiler-specific allocator
behavior, are reported in [KAFKA_MEMORY_AUDIT.md](../kafka/KAFKA_MEMORY_AUDIT.md).
The 30-minute canonical replay completed 2332 deliveries but its final close
returned an error (native child exit 13); no successful sustained cleanup is
claimed. A short real broker-idle follow-up reproduced close code 4/native 104
under Seed/canonical (client exit 8), documented as R-02. Seed's retained RSS is a deployment blocker for unbounded workloads; a finite
canonical test does not certify all workloads. The fresh audit did not rebuild the
compiler bootstrap or rerun the entire compiler suite. Historical 97/105 results
and baseline failures below remain historical evidence.

Current sources, versions, gaps, exact compiler identities and command/exit logs:
[KAFKA_CAPABILITY_MATRIX.md](../kafka/KAFKA_CAPABILITY_MATRIX.md),
[KAFKA_PROTOCOL_COVERAGE.md](../kafka/KAFKA_PROTOCOL_COVERAGE.md), and
[KAFKA_GAP_ANALYSIS.md](../kafka/KAFKA_GAP_ANALYSIS.md).

---

The following implementation-time snapshot is preserved verbatim. Statements such
as “running” describe that historical snapshot, not the fresh audit status above.

# Native Kafka Consumer v1 results

Implementation is complete; final acceptance is still running. No fresh bootstrap
convergence or complete five-compiler real matrix is claimed until the corresponding
runner exits successfully. Evidence root:
`.bootstrap/kafka-broker/consumer-runs/impl-20261115T064019Z/`.

HEAD before work: `ac2c40aea9ab7c1a6403ef99185af2e7613d41ea`. The root contains
complete initial git inventory/diff, recoverable source backup, approved design,
authorization and hashes of 19,106 preexisting Producer evidence files.

## Acceptance gates

| Gate | Actual evidence/status |
| --- | --- |
| Phase 1 Metadata/Fetch/decoder | PASS Seed + canonical, `phase1-attempt2/`, exit 0 |
| Phase 2 classic groups/Range | PASS Seed + canonical, `phase2-attempt2/`, exit 0 |
| Phase 3 heartbeat/session/rebalance/Leave | PASS Seed + canonical, `phase3-attempt3/`, exit 0 |
| Phase 4 explicit ACK/offset management | PASS Seed + canonical, `phase4-attempt2/`, exit 0 |
| Final real five-compiler matrix | Running, `matrix-attempt6/` |
| Native commit fault matrix | PASS all 20 cases, `commit-fault-attempt7/`, exit 0 |
| Additional real crash/fencing/live failover matrix | Running, `edge-attempt2/` |
| Existing Producer/TCP/ApiVersions checks | PASS; `producer-regressions.tsv`, `tcp-postimplementation.log` |
| Full compiler regressions | 97 PASS / 8 FAIL; `regressions/status.tsv` |
| Fresh official four-stage bootstrap | Running; `bootstrap.log`, `bootstrap/` |

Phase 1 tests cover exact native Producer-to-Consumer fields, broker-assigned offsets
and epochs, null/empty/binary keys and values, duplicate/null headers, timestamps,
CRC32C, malformed/truncated records, control-marker validation, compaction gaps,
delete horizon, overlapping batches, explicit compression rejection and legal Fetch
partial tails. Native socket peers exercise refusal, partial writes/fragmented
reads, correlation mismatch, invalid frame lengths, EOF and total request deadlines.

Real group and offset tests cover disjoint Range assignment, empty assignments,
service-driven heartbeats beyond a session, intentional service lapse, max-poll
expiry, reconnecting LeaveGroup, explicit ACK, manual and automatic commits,
unacknowledged replay, offset recovery, latest start, seek fencing, multiple topics,
partition growth and full-cluster outage recovery. Final runs exercise Seed,
canonical and the Stage2/3/4 compiler paths separately.

Additional real cases explicitly use SIGKILL before/after commit, test survivor
reassignment after peer departure, broker rejection of stale-generation commits,
stale ACK rejection after real rebalance/session loss, unknown-topic/out-of-range
errors and live single-broker leader/coordinator failover. Their final status is
reported separately; graceful-close restart tests are not crash evidence.

Native commit peers validate generation/member and exact ACK-gated wire positions.
Lost-response/timeout retries retain processed progress; partial responses confirm
only successful partitions; authorization failure remains terminal. These are peer
fault tests, not claims of ACL-configured real Kafka authorization testing.

## Final review corrections

Review and regressions corrected decoder overlap/control/delete-horizon handling,
reconnecting LeaveGroup, manual commit reconnect and mixed-error priority. The final
review also corrected poll-entry max-poll expiry, coordinator retry state surviving
full revocation, periodic subscribed metadata discovery, invalid UTF-8 header names,
and connect budgets exceeding heartbeat/session deadlines. Stable metadata refresh
runs every 30 seconds; topology change revokes ownership and rejoins. Blocking
connects honor role-specific heartbeat and ownership budgets. No compiler/runtime
implementation changes were made.

## Failed and superseded attempts

Every attempt is retained; no failed test is reclassified as PASS.

- Phase1 attempt1 passed its then-current tests; review additions required attempt2.
- Phase2 attempt1: canonical passed, Seed failed with an empty request. Seed IR
  omitted tuple-reassignment builder calls. Explicit pair declarations fixed the
  Consumer source; attempt2 passed both compilers.
- Phase3 attempt1: runner syntax failure after editing an executing shell script.
  Attempt2 exercised liveness; review found a reconnecting-close gap. Attempt3
  passed all scenarios after the correction.
- Phase4 attempt1 passed; review then strengthened reconnect/mixed-error behavior.
  Attempt2 passed both compilers. Failing unit exits 92/93 are preserved.
- Matrix attempt1: Seed broker recovery failed exit 16 because the scenario Producer
  used the old leader after Kafka elected broker 2. The native test helper now
  resolves current Metadata before publishing.
- Matrix attempt2: stopped to correct final-review findings; not acceptance.
- Matrix attempt3: Seed functional, processing-delay, partition-growth and full
  outage recovery passed. The large-Fetch benchmark failed exit 9 on a five-second
  request deadline. This remains a known performance/availability limitation.
- Matrix attempt4: compilation failed on a nested clock expression rejected by
  Seed borrow proof. A plain clock local resolved it. Synthetic unit liveness
  configuration was also corrected; final Seed units passed.
- Matrix attempt5: Seed and canonical completed all cases, including performance;
  Stage2 passed through partition growth, then Kafka restart failed with
  `OutOfMemoryError: Java heap space` in `SkimpyOffsetMap`/LogCleaner. This is a test
  server failure, not a Consumer PASS or a reclassified compiler regression.
- Commit fixture attempts1–4: fixture compilation failures while adapting to Seed
  ownership restrictions. Attempt5 passed; attempt6 found the nested clock argument;
  attempt7 reran all 20 cases successfully against the final Consumer source.
- Edge attempt1: all Seed scenario checks passed, including live leader/coordinator
  failover. Subsequent broker rejoin could not restore ISR under the small server
  heap; the runner was stopped and its logs retained. It is not five-label acceptance.

Final Consumer fixtures use process-local `-Xms128m -Xmx512m` and an 8 MiB Kafka
log-cleaner dedupe buffer. The broker helper exposes optional test overrides;
existing Producer defaults remain `-Xms128m -Xmx256m` with Kafka's default cleaner
configuration. No system Java or system configuration is changed.

## Compiler regressions and preservation

All 105 compiler checks were executed independently, including after failures.
The parser prerequisite passed. Results: **97 PASS, 8 FAIL**, matching the original
baseline. The eight remain failures:

1. `test/stdlib-native/test_collections.py` (Seed generic option return mismatch).
2. `canonical_enum_mir_check.sh` (undeclared std in isolated MIR fixture).
3. `canonical_aggregate_mir_check.sh` (same).
4. `canonical_cfg_mir_check.sh` (same).
5. `canonical_bitwise_mir_check.sh` (same).
6. `canonical_external_reachability_check.sh` (same).
7. `canonical_unit_shadow_production_check.sh` (undefined e).
8. `canonical_statement_boundary_ast_check.sh` (fixture result differs from 42).

Individual commands, statuses and logs are in `regressions/`. Baseline unchanged-HEAD
reproductions remain in the Producer evidence/report. No unrelated compiler fix was
introduced to hide these failures.

Producer v3 real acceptance passed under Seed and canonical, including ACK -1/0/1,
keys/headers/null/binary fields, batching, 512 KiB, partitions, broker errors and the
original independent record oracle. Producer and ApiVersions/TCP fault suites and
broker real integration passed under both compilers. All outputs use a fresh
`producer-regression-snapshot/`; historical Producer evidence is untouched.
All 19,106 historical hashes match. Preexisting implementation files are preserved;
only additive builder modes and optional broker test-resource overrides were added.
The approved DESIGN.md remains byte-identical.

## Performance and limitations

The reproducible benchmark uses Kafka 3.9.1, one topic/partition, 8192 messages,
256-byte values, native Producer batches of 64, ACK=1, Fetch max=16 KiB and delivery
limits 1 versus 128 (actual fetched record batches are 64). Production completes
before data polling. Throughput is finite 2 MiB backlog-drain throughput; latency
includes preload/backlog residence and is not concurrent steady-state latency.
There is no warmup. Other acceptance/bootstrap work shares the host.

The measured native process contains both Producer preload and Consumer drain.
Its CPU and RSS are sampled every 20 ms; GNU time also records process
family resource usage. Eight 1024-record windows record memory during consumption.
The initial Seed observations were 579/588 records/s for delivery limits 1/128;
final comparable measurements will be tabulated from the final run. Native Producer
batch throughput is recorded in the same workload for context. No external client
throughput baseline is claimed.

RSS grows during consumption: initial Seed runs rose from about 142 to 447 MiB for
single delivery, and about 148 to 496 MiB for batch delivery. This is unresolved
retained-memory behavior, not proof of stable bounded memory or indefinite sustained
operation. No unrelated runtime/allocator change is authorized or included.
The 768 KiB Fetch benchmark's deadline failure remains explicit; the tuned 16 KiB
benchmark does not establish large-response acceptance. Supported scope is
uncompressed, read-uncommitted, PLAINTEXT, literal IPv4, eager classic Range groups;
applications must call poll/service regularly. No background heartbeat, SASL/TLS,
compression, cooperative/static membership or transactional/exactly-once processing
guarantee; read-committed transaction filtering is unsupported.
