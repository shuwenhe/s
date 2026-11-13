# Isolated Apache Kafka broker fixture

Source `misc/scripts/kafka-broker.sh` from Bash, then install cleanup before starting:

```bash
set -euo pipefail
source misc/scripts/kafka-broker.sh
trap kafka_stop EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
workdir=$(mktemp -d)
kafka_start "$workdir" "$broker1_port" "$broker2_port" "$controller_port"
kafka_create_topic s-test 2 2
# S clients use $KAFKA_BOOTSTRAP and discover $KAFKA_BROKER2 in metadata.
kafka_stop
kafka_start "$workdir" "$broker1_port" "$broker2_port" "$controller_port"
# Existing cluster ID, topic metadata, and record logs survive this restart.
```

The runner must supply three distinct, available loopback ports. There are two real
broker processes (IDs 1 and 2) and a dedicated KRaft controller (ID 3). All mutable
cluster files live in the supplied directory. Cleanup signals and waits only for
PIDs started by this shell, checking their configuration argument before signaling.
Do not run this fixture in a directory used by another running fixture.

`kafka_prepare` downloads the official Scala 2.13 Kafka 3.9.1 distribution into
`${KAFKA_CACHE:-/tmp/s-kafka-3.9.1}` and verifies its pinned Apache SHA512 before
extracting or using it. `KAFKA_HOME` is exported. Dependencies are Bash, Java,
curl, tar, sha512sum and standard Unix utilities; missing dependencies and startup
failures return nonzero. Logs remain in the supplied directory for diagnosis.

An optional fifth argument adds a TLS listener to broker 1, using an isolated
self-signed PEM certificate whose SAN contains localhost and 127.0.0.1. OpenSSL is
required for this mode. `KAFKA_TLS_BOOTSTRAP` is exported; the certificate to trust
is `$KAFKA_WORKDIR/server.crt`. This listener is suitable for a single-partition
TLS smoke topic assigned explicitly to broker 1:

```bash
"$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "$KAFKA_BOOTSTRAP" \
    --create --topic s-tls --replica-assignment 1
```

Use plaintext for tests that discover and route between both brokers. The helper
runs official Java storage, broker, and topic administration tools; producer and
consumer protocol tests must use the repository's native S implementation.

Primary references:

- [Official Kafka 3.9 quick start](https://kafka.apache.org/39/getting-started/quickstart/)
- [Official Kafka 3.9 broker configuration](https://kafka.apache.org/39/configuration/broker-configs/)
- [Apache 3.9.1 archive and SHA512](https://archive.apache.org/dist/kafka/3.9.1/)
