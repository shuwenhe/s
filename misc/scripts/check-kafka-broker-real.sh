#!/usr/bin/env bash
# Pinned official Kafka server; the client is pure native S.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
work="$root/.bootstrap/kafka-broker/real"
mkdir -p "$work"
compiler=${1:-"$root/bin/s_compiler"}
label=${2:-native}
sh misc/scripts/build-kafka-broker-test.sh integration "$work/client-$label" "$compiler" > "$work/build-$label.log" 2>&1
if [[ "${KAFKA_USE_EXISTING:-0}" != 1 ]]; then
    if ! command -v java >/dev/null; then
        echo 'BLOCKED: Kafka 3.9.1 server requires Java; no Java runtime is on PATH.' >&2
        exit 2
    fi
    export KAFKA_CACHE="$root/.bootstrap/kafka-broker/distribution"
    source misc/scripts/kafka-broker.sh
    trap kafka_stop EXIT
    kafka_start "$work/cluster" 9092 19093 19094
fi
timeout 20 "$work/client-$label" | tee "$work/client-$label.log"
