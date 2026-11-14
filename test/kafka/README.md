# Native Kafka broker milestone

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

Only ApiVersions v0 negotiation is covered. Flexible response headers, TLS/SASL,
DNS, Producer, Consumer and consumer groups are outside this milestone.
