# Kafka reliability and feature roadmap

Audit date: 2026-11-15. This is a prioritized recommendation, not authorization to
implement features during the audit. Findings and source evidence are in
[KAFKA_GAP_ANALYSIS.md](KAFKA_GAP_ANALYSIS.md); detailed memory evidence is in
[KAFKA_MEMORY_AUDIT.md](KAFKA_MEMORY_AUDIT.md).

Priorities are conditional on deployment needs. Complexity is relative engineering
risk, not a delivery estimate: S=localized, M=several components, L=runtime/transport
or multi-API state machine, XL=multiple interacting correctness domains. Estimating
calendar duration before settling the runtime/linkage and deployment contracts
would be misleading. No external package, Java runtime or system configuration
was installed or changed for this audit.

## Gate 0 — memory correctness and reproducible acceptance (P0)

Evidence: M-01/M-02/T-01. Consumer feature tests can pass while RSS grows; Seed and
canonical have materially different allocators. Do not add compression, extra
in-flight Fetch roles or pooling to this allocation pattern first.

Recommended sequence:

1. Establish controlled transport-only, decoder-only, empty-poll, delivery/ACK,
   commit, rejoin and close allocation measurements using exact compiler hashes.
   Preserve the present six-size sweep and 30-minute replay baseline.
2. Compare lifecycle-owned buffer reuse, scoped ownership/arenas and runtime
   reclamation approaches. Reuse gives local control but needs a safe byte-buffer
   abstraction; scoped allocation needs proof no delivery/reference escapes;
   tracing/lifetime reclamation has broader compiler/runtime risk. Prefer a
   measured local ownership design where it is sound, and explicitly address
   Seed's effectful allocation policy where local field clearing cannot reclaim.
3. Clear transient decoder, delivery and commit state on close/revoke with tests
   for mid-read/mid-CRC/mid-record cancellation. Confirm delivered data remains
   valid for the documented application ownership period.
4. Repair the stock benchmark entrypoint selection; retain simulator coverage
   separately. Add ACK expiry and record-count/frame-boundary regressions.
5. Require at least 30 minutes of sustained *new data* at each required payload
   size within supported limits, repeated rebalance and cleanup, with native
   process RSS/anonymous memory, CPU, FD count and exact byte/offset verification.
   Expand to multi-hour runs and deployment rates. Explicitly distinguish a
   bounded allocator high-water mark from a rising live set. Replay alone does
   not satisfy all of these release gates.

Exit criteria: no lost/implicitly ACKed application records; compiler-specific
memory ceiling and stable late-window slope under agreed workload; no FD leak;
close/rebalance reference cleanup verified; deterministic stock acceptance passes.
No numeric universal memory ceiling is invented by this audit.

## Gate 1 — recovery and performance qualification (P1)

Evidence: R-01/R-02/P-01/C-02/C-03. Fix remote-idle close recovery with
bounded reconnect/Leave retry and explicit sustained-close diagnostics first. Enumerate per-API errors and retry/fencing states,
include unknown/mixed/partial responses, verify commit ambiguity and leader changes
while data/commit requests are active. Add real ACL denial and quota fixtures.
Test 1/16/128+ partitions, skewed traffic and multiple members; separate throughput,
p95/p99 service/poll/commit latency, backlog residence, CPU and memory. Capture
broker resources and run isolated host controls.

Retain explicit record/frame caps until a bounded decode window design exists.
Improve byte-array/string conversion, copy behavior and CRC only after profiles
identify their share of cost. A faster CRC alone cannot fix process-lifetime
allocation. Do not compare current preload/drain numbers to a steady-state Java
client benchmark without matching method and workload.

## Advanced-feature requirements

All features below remain NOT IMPLEMENTED in Kafka unless explicitly described as
PARTIAL. Each row ties the current source gap to dependencies, runtime/compiler
needs, compatibility and validation. Required tests run under Seed/canonical and
available Stage2/3/4 paths independently, with identity/build/run evidence.

| Feature / priority / complexity | Current source evidence and missing behavior | Dependencies and compiler/runtime needs | Compatibility implications | Required acceptance |
| --- | --- | --- | --- | --- |
| TLS / P1 when required, after Gate0 / L | `consumer_transport.s` and `broker.s` use TCP only. `src/std/tls.s` has a separate intrinsic/OpenSSL bridge; no Kafka transport integration. | Decide native-only vs optional OpenSSL linkage; define common incremental transport operations, handshake/read/write deadlines, trust roots, hostname verification, SNI, credential lifetime and error mapping. Preserve four-role ownership and service fairness. | Enabling TLS must be explicit; existing standalone client has no OpenSSL dependency. A TLS wrapper is not proof of secure Kafka endpoint identity or nonblocking liveness. | TLS-only real broker, trusted/untrusted/expired/name-mismatched certs, fragmented handshake, handshake timeout, heartbeat under TLS load, reconnect/close, optional mTLS and rotation if required. |
| SASL/PLAIN / P1 when required, after TLS / M | No SaslHandshake/SaslAuthenticate builder/state in `src/std/kafka`; `error_authentication` alone is not support. | Version negotiation, bounded mechanism exchange before role RPCs, credential configuration/secret lifetime, protocol framing and auth error handling. TLS prerequisite for credential confidentiality. | Both Producer and every Consumer role must authenticate; fail closed on unsupported mechanism and invalid credentials. No plaintext credential default. | Real SASL_SSL broker, correct/wrong/missing credentials, unavailable mechanism, authorization distinct from authentication, reconnect and secret rotation policy. |
| SASL/SCRAM / P1/P2 deployment-dependent, after TLS/SASL transport / L | No SCRAM exchange/nonce/proof/server-signature validation in Kafka. Existing `src/std/crypto.s` supplies SHA256/HMAC/PBKDF2 helpers, not an audited SASL client. | Select SCRAM-SHA-256/512 requirements; existing SHA-256 primitives need vectors/security review; SHA-512 cannot be presumed available. Secure random intrinsic, base64, name escaping, iteration bounds, constant-time comparison and credential erasure strategy. | Mechanism must match broker; CPU-heavy PBKDF2 cannot silently starve heartbeat/caller budgets. Avoid logging credentials/proofs. | RFC vectors, wrong proof/server signature, nonce/salt/iteration attacks, malformed messages, real SCRAM broker, reconnect and compiler parity. |
| gzip / P2 if needed for interoperability / L | `consumer_decode.s::consumer_decoder_step` rejects codec bits !=0; Producer attributes always zero. | Deflate/gzip codec or optional library ABI; CRC before decompress, decompression cap, streaming input/output ownership, CPU budget and backpressure. | Compression is per batch; must read existing compressed topics before claiming consume compatibility. Optional native linkage policy required. | Independent Kafka/Java fixtures both directions, truncation/CRC failures, expansion bombs, memory ceiling, mixed batches, timestamps/headers/offsets across codecs. |
| Snappy / P2 / L | Same codec rejection; no Kafka Snappy framing implementation. | Snappy codec plus Kafka/Xerial framing compatibility, bounded block decoder, runtime byte buffers. | A raw Snappy decoder alone is insufficient for Kafka data compatibility. | Official-client compressed fixtures, framing versions/chunks, invalid lengths, expansion caps and RSS under sustained decoding. |
| LZ4 / P2 / L | Same rejection; no Kafka LZ4 frame/codec implementation. | LZ4 framing/checksum handling and magic-2 format scope; bounded block assembly. | Explicitly decide whether legacy Kafka quirks/formats remain excluded; do not imply magic-0/1 support. | Independent Kafka LZ4 bytes, corrupt block/frame checksums, truncation, output caps, mixed uncompressed/compressed batches and memory/CPU. |
| Zstandard / P2/P3 / L | No codec; fixed Produce v3 and Fetch v4. | Zstd library/native codec, frame/window/dictionary bounds, protocol version negotiation and bounded streaming decompression. | Recheck broker/client minimum API versions for Zstd; upgrading only codec bits is insufficient. Larger runtime surface and ABI support. | Real broker and official client cross-oracle, protocol negotiation rejection, large windows/dictionaries/corruption and sustained memory. |
| Idempotent Producer / P1 if automatic retries required, after routing/recovery / L | `batch.s::encode_record_batch`: id/epoch/sequence=-1; no InitProducerId. | Producer identity acquisition, per-partition sequence/epoch tracking, duplicate/out-of-order/fencing handling, bounded in-flight policy, retry ambiguity and ordering semantics. | New opt-in mode/config and error contract; do not silently retry existing nonidempotent API. Broker version negotiation and identity expiry/restart policy. | Drop response after actual append, reconnect/retry exact bytes, duplicate sequence, epoch fencing, leader failover, identity reset; independently count broker records and offsets. |
| Transactions / P3, deferred / XL | `produce.s::build_produce_request` uses null transactional ID; no transaction lifecycle/coordinator APIs; Consumer isolation=0. | Idempotence first; FindCoordinator transaction mode, InitProducerId, AddPartitionsToTxn, AddOffsetsToTxn/TxnOffsetCommit, EndTxn, abort/fencing/timeouts; read-committed LSO/aborted filtering on consume. | Explicit new transaction API and application semantics; no exactly-once claim from atomic batch or ACK=-1. Cross-service side effects still need their own coordination. | Commit/abort, crash at every lifecycle point, concurrent/fenced transactional IDs, coordinator migration, read-committed visibility, atomic offset+produce outcomes and long fault matrices. |
| DNS / P1 for hostname clusters, after Gate0 / M–L | `src/std/tcp.s::_address` accepts IPv4 digits only; metadata host passed directly. | Resolver strategy (native async or explicit optional system resolver), A-record iteration, TTL/cache expiry, cancellation and request/session budgets. | All bootstrap/advertised/coordinator names must resolve. Blocking libc resolution must not undermine standalone portability or heartbeats without explicit contract. | Hostname bootstrap + advertised listeners, changing A records, multiple answers, NXDOMAIN, timeout, expiry, failover and bounded resolver memory. |
| IPv6 / P2 deployment-dependent / M–L | TCP intrinsic currently takes a packed IPv4 integer; no sockaddr_in6 Kafka path. | Address model/intrinsic ABI and platform syscall extensions, literal parser, scope IDs if required, bracketed endpoint syntax and dual-stack policy. | Preserve IPv4 ABI/defaults; avoid representing IPv6 in an int. Reconcile DNS address-family selection. | IPv6-only and dual-stack real brokers, literals/hostnames, invalid scope/address forms, connect/recovery and compiler/runtime ABI parity. |
| Multiple broker discovery / PARTIAL Consumer, NOT IMPLEMENTED Producer / P1 / M | `consumer_metadata.s::consumer_parse_metadata`, `consumer.s::_kc_metadata_step` already maintain broker list/leader mapping; Producer endpoint fixed. | Reuse audited metadata codecs, routing/cache invalidation, leader errors and endpoint policy; Producer ordering/idempotent retries design. | Do not replace working Consumer discovery. Maintain single-owner routing state and explicit partition API compatibility. | Bootstrap loss, leader/coordinator moves, stale metadata, partition growth, advertised-host errors, multiple unreachable bootstrap entries and no duplicate retry surprise. |
| Connection pooling / P3, deferred / L | Four dedicated Consumer role sockets are not a general pool; Producer one connection. | Prove memory bounds first, then per-broker owners, fairness, correlation demultiplexing/in-flight limits, FD/resource cap and idle eviction. Threading is optional and not a prerequisite. | Preserve heartbeat separation; changing concurrency/ownership can invalidate current sequential assumptions and ordering. | Socket/FD limit pressure, cancellation, pool eviction during requests, reconnect storms, skewed partitions, heartbeats/commits under load and sustained RSS. |

Feature requirements are grounded in the pinned Kafka
[Produce schema](https://github.com/apache/kafka/blob/3.9.1/clients/src/main/resources/common/message/ProduceRequest.json),
[Fetch schema](https://github.com/apache/kafka/blob/3.9.1/clients/src/main/resources/common/message/FetchResponse.json),
and existing repository transport/codec code. Security mechanism requirements also reference
[RFC 4616 (PLAIN)](https://www.rfc-editor.org/rfc/rfc4616),
[RFC 5802 (SCRAM)](https://www.rfc-editor.org/rfc/rfc5802) and
[RFC 7677 (SCRAM-SHA-256)](https://www.rfc-editor.org/rfc/rfc7677).
They require standards and threat review during design; this audit is not a cryptographic
certification of the repository's primitives.

## Proposed release ordering

Memory ownership/reclamation and cleanup → reproducible fault/real acceptance →
recovery/bounds and workload performance → deployment-required TLS/SASL/DNS →
Producer routing and deliberate retry policy → idempotence and required
compression → broader protocol features. IPv6 is driven by actual network needs.
Transactions, exactly-once claims, generic pooling and modern cooperative/new-group
protocols remain deferred until the lower gates have measurable acceptance.

Before choosing a specific feature design, decide the deployed compiler, expected
record/partition/member scale, memory ceiling, liveness budget, security requirements
and optional external-library policy. The audit supplies current evidence and
priorities; it does not silently select a new runtime/linkage architecture.
