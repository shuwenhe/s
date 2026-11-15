# Current Kafka test status — 2026-11-15 audit

Native Producer **and Consumer** are implemented. Current source-verified scope,
fresh five-compiler test results, memory measurements and known limits are in
[doc/kafka/KAFKA_CAPABILITY_MATRIX.md](../../doc/kafka/KAFKA_CAPABILITY_MATRIX.md).
Consumer reproduction commands are in
[TESTING.md](../../doc/kafka-consumer/TESTING.md). Use the standalone
`build-kafka-broker-test.sh` path. Its consumer-benchmark glob currently includes
two main functions; the fresh audit retained the failure and ran a copied builder
selecting `consumer-benchmark/main.s`. See finding T-01 and the audit evidence
ledger before reproducing the full matrix. Existing unit modes are unaffected.

The Producer Phase 1 description below is historical; its statement that Consumer
was not yet started applies to that phase only. Historical evidence is preserved.

---

# Native Kafka broker and producer

The client and fault peer are written in S. The standalone build path needs no
OpenSSL bridge or non-S client. Linux/amd64 and literal IPv4 addresses are supported.

```sh
sh misc/scripts/build-kafka-broker-test.sh unit .bootstrap/kafka-broker/unit
.bootstrap/kafka-broker/unit
bash misc/scripts/check-kafka-broker-faults.sh
bash misc/scripts/check-kafka-broker-faults.sh "$PWD/bin/s_seed" seed
bash misc/scripts/check-kafka-broker-real.sh
```

The real runner requires an existing Java runtime on PATH, downloads the pinned
Kafka 3.9.1 distribution via the existing checksum-verified broker helper, starts
two brokers and a controller, tests localhost:9092, and stops only owned processes.
All distribution files, cluster data, native executables and logs are under
`.bootstrap/kafka-broker/`. It does not install Java or change system settings.
If a Kafka 3.9.1 broker is already listening on localhost:9092:

```sh
KAFKA_USE_EXISTING=1 bash misc/scripts/check-kafka-broker-real.sh
```

This mode assumes the operator has verified the server version. It does not
stop an externally owned broker. Missing or invalid brokers fail the test.
Fault tests on port 19092 are distinct from real Kafka acceptance on port 9092.
Run fault suites serially because they share a fixed loopback port.

## API

```s
b, connect_error := std.kafka.broker_connect("127.0.0.1", 9092, "my-s-client", 5000)
// Check connect_error.code before using b.
versions, negotiation_error := std.kafka.broker_api_versions(b*, 5000)
close_error := std.kafka.broker_close(b*)
```

A connected broker owns its socket; do not copy it or run simultaneous requests.
`broker_send_request` accepts an unframed request with a non-null client ID in a
v1 request header and correlation equal to `b.correlation_id`. It consumes that
ID when beginning I/O and validates/strips the response's four-byte correlation
header. IDs advance from 1 through INT32_MAX, then wrap to 1; only one request is
in flight. `broker_api_versions` builds ApiVersions v0 automatically.

Requests and responses are capped at 1 MiB. Positive timeouts through INT32_MAX
milliseconds bound the entire write/header/body exchange using a monotonic clock.
A failed transport, malformed frame or mismatched response closes the connection.
Malformed API bodies also close it when using `broker_api_versions`. Native TCP
errno and Kafka error codes are preserved in `error.native_code`.

## Producer Phase 1

Implemented: negotiated Produce v3, uncompressed RecordBatch v2, CRC32C,
keys/values (including binary/null/empty), duplicate message headers, batching,
explicit partition and ACK -1/0/1, base offsets, broker status and timeout handling.
The native producer has no Java/C++ client dependency. The supplied endpoint must
be the partition leader. See `src/std/kafka/README.md` for signatures and semantics,
and `test/kafka/producer/main.s` for an executable producer example.

```sh
# Unit + socket fault suites. Run serially: port 19092 is shared.
bash misc/scripts/check-kafka-producer-faults.sh
bash misc/scripts/check-kafka-producer-faults.sh "$PWD/bin/s_seed" seed
# Preserve/test existing broker functionality too:
bash misc/scripts/check-kafka-broker-faults.sh
bash misc/scripts/check-kafka-broker-faults.sh "$PWD/bin/s_seed" seed

# Optional test-only Java runtime; no system installation or configuration:
source misc/scripts/kafka-java.sh
kafka_test_java
# Both compilers, official Kafka 3.9.1 server, independent consumer byte oracle,
# plus serialization/latency/throughput/RSS measurements:
bash misc/scripts/check-kafka-producer-real.sh
```

The real producer runner creates topics with explicit replica assignments on two
brokers. It publishes 11 records per compiler, verifies exact keys, values,
headers, partitions and offsets using the official console consumer, and exercises
unknown-topic and wrong-leader broker errors. It includes 512 KiB values and
ACK=0 followed by an acknowledged barrier on the same socket. Fixtures also test
refusal, unsupported negotiation, malformed responses, EOF, timeouts and local
input rejection without correlation changes. Unit tests check independent fixed
wire bytes/CRC, every truncated prefix, structural mutations with valid CRC,
int64 timestamp extremes, exact 4096-record/header and 1 MiB batch boundaries.

Test Java is pinned Amazon Corretto 17.0.21.0.11, downloaded only below
`.bootstrap/kafka-broker/`. Vendor HTTPS `latest_checksum` returned MD5
`d6e3ba38b0c0e17b051e0655bdb9a563`, matching the archive; the SHA256
`8f9a2ddb131ec5317419f2b0769240fe22ce27f8a0ae43f5346d53e1c8aec6a0`
is pinned in the helper for repeatability. Kafka's existing helper verifies the
pinned 3.9.1 distribution with its Apache SHA512. No download is linked into the
native client. Runners fail on missing prerequisites/builds/brokers; no silent skips.
Owned broker shutdown is bounded and cannot kill a process whose config identity
does not match. Test fixtures may be force-stopped after 15 seconds of graceful
shutdown when the controller is already gone.

Logs, binaries, official-consumer byte outputs and performance measurements are
under `.bootstrap/kafka-broker/phase1/`. See `doc/kafka-producer-phase1-report.md`
for the measured results, failed attempts and final verification status.

Flexible response headers, TLS/SASL, DNS, compression, idempotence, transactions,
automatic routing/retry/recovery, Consumer and consumer groups remain unsupported.
No Consumer implementation was begun in Phase 1.
