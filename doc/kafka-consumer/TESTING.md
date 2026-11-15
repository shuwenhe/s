# Consumer test reproduction

From repository root. Use a fresh output directory for every invocation; never
reuse Producer Phase 1 evidence directories. Java/Kafka downloads stay under
.bootstrap/kafka-broker/. Fixed fault port 19092 means suites must run serially;
real cluster ports 9092/19093/19094 must not be used by another local test.

```sh
sh misc/scripts/build-kafka-broker-test.sh consumer-unit NEW_DIR/unit-native
NEW_DIR/unit-native
sh misc/scripts/build-kafka-broker-test.sh consumer-unit NEW_DIR/unit-seed "$PWD/bin/s_seed"
NEW_DIR/unit-seed
bash misc/scripts/check-kafka-consumer-phase1.sh NEW_PHASE1_DIRECTORY
bash misc/scripts/check-kafka-consumer-groups.sh NEW_GROUP_DIRECTORY
KAFKA_CONSUMER_LIVENESS=1 bash misc/scripts/check-kafka-consumer-groups.sh NEW_LIVENESS_DIRECTORY
bash misc/scripts/check-kafka-consumer-offsets.sh NEW_OFFSETS_DIRECTORY
bash misc/scripts/check-kafka-consumer-acceptance.sh NEW_ACCEPTANCE_DIRECTORY
```

These commands fail on missing prerequisites or failures. The Phase 1 runner uses
real native Producer v3 messages and compares decoded fields directly. Groups use
concurrent standalone native S consumers and independently compare disjoint Range
assignment sets. Liveness scenarios distinguish regular service beyond a session,
intentional service lapse, max-poll expiry, and reconnecting LeaveGroup.

RESULTS.md records actual commands/results, failed attempts and remaining gates.
The full acceptance runner executes Seed, canonical, Stage2, Stage3 and Stage4 with
real Kafka, native fault peers, processing delays, partition growth, offsets,
full-cluster recovery and reproducible backlog-drain performance. Additional crash,
fencing and live failover checks are recorded separately. Prior eight compiler
regressions remain failures. Old bootstrap evidence is not a fresh bootstrap run.

Consumer acceptance uses a process-local 512 MiB Java heap and an 8 MiB log-cleaner
dedupe buffer so repeated restart of the growing test topic set does not exhaust
Kafka's small original fixture heap. The original Producer resource defaults remain
unchanged. Performance is measured on a shared host; see RESULTS.md for method and
observed RSS growth rather than inferring sustained memory stability.

```sh
bash misc/scripts/check-kafka-consumer-commit-faults.sh NEW_COMMIT_FAULT_DIRECTORY
bash misc/scripts/check-kafka-consumer-edge.sh NEW_EDGE_DIRECTORY
python3 misc/scripts/summarize-kafka-consumer-performance.py COMPLETED_ACCEPTANCE_DIRECTORY
```

The edge runner uses separate real broker ports 29092/29093/29094; it can run
alongside the main matrix if the host has sufficient resources. SIGKILL fixture
checks require observed exit 137, followed by successful offset0/offset1 restart.
It also checks real stale-generation commits, survivor reassignment, session-loss
ACK fencing, broker errors and single-broker failover. `KAFKA_EDGE_LABELS=seed`
selects a targeted run. `KAFKA_CONSUMER_STAGE_ROOT` selects Stage2/3/4 binaries for
the edge runner (default: retained Producer bootstrap). The S edge source is in
`test/kafka/consumer-edge/main.s`; the standard builder supports `consumer-edge`.
