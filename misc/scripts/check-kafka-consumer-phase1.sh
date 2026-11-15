#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
run=${1:?provide a fresh evidence directory}
mkdir -p "$run"
source misc/scripts/kafka-java.sh
kafka_test_java
export KAFKA_CACHE="$root/.bootstrap/kafka-broker/distribution"
source misc/scripts/kafka-broker.sh
trap kafka_stop EXIT
# All real outputs are new. Never reuse Producer cluster/evidence directories.
kafka_start "$run/cluster" 9092 19093 19094
for label in native seed; do
    compiler="$root/bin/s_compiler"
    [[ "$label" != seed ]] || compiler="$root/bin/s_seed"
    work="$run/$label"
    mkdir -p "$work"
    for mode in consumer-unit consumer-fault-client consumer-fault-peer consumer-phase1; do
        sh misc/scripts/build-kafka-broker-test.sh "$mode" "$work/$mode" "$compiler" > "$work/build-$mode.log" 2>&1
    done
    "$work/consumer-unit" | tee "$work/unit.log"
    "$work/consumer-fault-client" refused | tee "$work/refused.log"
    for mode in valid mismatch negative short oversize eof-header eof-body timeout slow decode-timeout; do
        "$work/consumer-fault-peer" "$mode" > "$work/peer-$mode.log" 2>&1 &
        peer=$!
        ready=0
        for ((i=0;i<200;i++)); do
            if rg -q '^ready$' "$work/peer-$mode.log"; then ready=1; break; fi
            sleep 0.01
        done
        [[ "$ready" = 1 ]] || { kill "$peer" 2>/dev/null || true; wait "$peer" || true; exit 1; }
        status=0
        timeout 15 "$work/consumer-fault-client" "$mode" > "$work/client-$mode.log" 2>&1 || status=$?
        wait "$peer" || { cat "$work/peer-$mode.log"; exit 1; }
        cat "$work/client-$mode.log"
        [[ "$status" = 0 ]] || { echo "FAIL $label $mode exit=$status"; exit 1; }
    done
    topic="s-consumer-phase1-$label-$(date +%s)-$$"
    "$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "$KAFKA_BOOTSTRAP" --create --topic "$topic" --replica-assignment '1:2,1:2' > "$work/topic.log" 2>&1
    timeout 60 "$work/consumer-phase1" "$topic" | tee "$work/real.log"
done
