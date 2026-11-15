#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
run=${1:?fresh evidence directory}
mkdir -p "$run"
source misc/scripts/kafka-java.sh
kafka_test_java
export KAFKA_CACHE="$root/.bootstrap/kafka-broker/distribution"
source misc/scripts/kafka-broker.sh
trap kafka_stop EXIT
kafka_start "$run/cluster" 9092 19093 19094
for label in native seed; do
    compiler="$root/bin/s_compiler"
    [[ "$label" != seed ]] || compiler="$root/bin/s_seed"
    work="$run/$label"
    mkdir -p "$work"
    sh misc/scripts/build-kafka-broker-test.sh consumer-unit "$work/unit" "$compiler" > "$work/build-unit.log" 2>&1
    "$work/unit" | tee "$work/unit.log"
    sh misc/scripts/build-kafka-broker-test.sh consumer-offsets "$work/client" "$compiler" > "$work/build-client.log" 2>&1
    topic="s-consumer-offset-$label-$(date +%s)-$$"
    "$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "$KAFKA_BOOTSTRAP" --create --topic "$topic" --replica-assignment '1:2' > "$work/topic.log" 2>&1
    timeout 120 "$work/client" "$topic-group" "$topic" | tee "$work/real.log"
done
