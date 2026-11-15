# Native Kafka Consumer v1

The Consumer is implemented. A fresh 2026-11-15 capability audit executed the
five compiler paths separately against Apache Kafka 3.9.1; the complete fresh
functional matrix passed with the benchmark entrypoint isolated as documented in
finding T-01. This does not establish general production readiness or memory bounds.
See [capability/evidence matrix](../kafka/KAFKA_CAPABILITY_MATRIX.md),
[memory audit](../kafka/KAFKA_MEMORY_AUDIT.md) and [gap analysis](../kafka/KAFKA_GAP_ANALYSIS.md).

The approved implementation architecture/limits remain in DESIGN.md. PLAN.md and
the historical section of RESULTS.md preserve the implementation-time ledger;
use the fresh audit reports for current verification status.

The Consumer is native S, Linux/amd64, literal IPv4 and PLAINTEXT. It uses classic
groups with eager Range assignment and incremental, single-owner socket I/O.
There are no background threads or external Kafka client libraries. Java is only
repository-local server/admin test infrastructure.

Supported record scope: uncompressed magic-2 batches, read-uncommitted visibility,
binary/null/empty keys and values, duplicate/null/empty headers, broker offsets,
CreateTime/LogAppendTime, compaction gaps/delete horizon and validated transaction
control-marker suppression. Compression codecs other than zero are explicit
errors; no invalid CRC or malformed complete batch is silently accepted.

Applications must regularly call poll/service for heartbeats. Service does not
mean processing acknowledgment. ACK and commit are separate; no exactly-once claim.
See API.md for current interface status and the service/ACK contract. Functional acceptance is distinct from sustained memory and deployment
qualification. Seed allocation growth, closed-object retained fields and strict
frame/record-count limits remain explicit. TLS/SASL, DNS/IPv6, compression,
idempotent/transactional production and read-committed consumption are unsupported.
See TESTING.md for commands and API.md for defaults and ownership.
