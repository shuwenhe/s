#!/usr/bin/env bash
# Real Kafka 3.9.1 server and independent official console-consumer oracle.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
work="$root/.bootstrap/kafka-broker/phase1/real"
mkdir -p "$work"
source misc/scripts/kafka-java.sh
kafka_test_java
export KAFKA_CACHE="$root/.bootstrap/kafka-broker/distribution"
source misc/scripts/kafka-broker.sh
trap kafka_stop EXIT
kafka_start "$work/cluster" 9092 19093 19094
for label in native seed; do
    compiler="$root/bin/s_compiler"
    [[ "$label" != seed ]] || compiler="$root/bin/s_seed"
    topic="s-producer-${label}-$(date +%s)-$$"
    "$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_WORKDIR/admin.properties" --create --topic "$topic" --replica-assignment '1:2,1:2' > "$work/topic-$label.log" 2>&1
    "$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "$KAFKA_BOOTSTRAP" --describe --topic "$topic" >> "$work/topic-$label.log" 2>&1
    sh misc/scripts/build-kafka-broker-test.sh producer "$work/client-$label" "$compiler" > "$work/build-$label.log" 2>&1
    /usr/bin/time -v -o "$work/resources-$label.log" timeout 120 "$work/client-$label" "$topic" | tee "$work/client-$label.log"
    for partition in 0 1; do
        count=10
        [[ "$partition" != 1 ]] || count=1
        timeout 30 "$KAFKA_HOME/bin/kafka-console-consumer.sh" --bootstrap-server "$KAFKA_BOOTSTRAP" --topic "$topic" --partition "$partition" --offset earliest --max-messages "$count" --timeout-ms 20000 --property print.partition=true --property print.offset=true --property print.headers=true --property print.key=true > "$work/consumed-$label-$partition.bin" 2> "$work/consumer-$label-$partition.log"
    done
    python3 test/kafka/producer/verify.py "$work/consumed-$label-0.bin" "$work/consumed-$label-1.bin" | tee "$work/oracle-$label.log"
    bench_topic="$topic-benchmark"
    "$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "$KAFKA_BOOTSTRAP" --create --topic "$bench_topic" --replica-assignment '1:2' > "$work/benchmark-topic-$label.log" 2>&1
    sh misc/scripts/build-kafka-broker-test.sh producer-benchmark "$work/benchmark-$label" "$compiler" > "$work/benchmark-build-$label.log" 2>&1
    /usr/bin/time -v -o "$work/benchmark-resources-$label.log" timeout 120 "$work/benchmark-$label" "$bench_topic" | tee "$work/benchmark-$label.log"
done
printf 'Real Kafka 3.9.1 producer acceptance (Seed + canonical): PASS\n'
