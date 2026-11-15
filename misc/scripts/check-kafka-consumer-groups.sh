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
    "$work/unit" > "$work/unit.log" 2>&1
    sh misc/scripts/build-kafka-broker-test.sh consumer-group "$work/client" "$compiler" > "$work/build-client.log" 2>&1
    topic="s-consumer-group-$label-$(date +%s)-$$"
    "$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "$KAFKA_BOOTSTRAP" --create --topic "$topic" --replica-assignment '1:2,1:2,2:1,2:1' > "$work/topic.log" 2>&1
    timeout 40 "$work/client" "$topic-single" single "$topic" single > "$work/single.log" 2>&1
    timeout 40 "$work/client" "$topic-pair" first "$topic" pair > "$work/first.log" 2>&1 &
    first=$!
    timeout 40 "$work/client" "$topic-pair" second "$topic" pair > "$work/second.log" 2>&1 &
    second=$!
    status1=0; status2=0
    wait "$first" || status1=$?
    wait "$second" || status2=$?
    cat "$work/single.log" "$work/first.log" "$work/second.log"
    [[ "$status1" = 0 && "$status2" = 0 ]] || { echo "FAIL pair $label first=$status1 second=$status2"; exit 1; }
    python3 - "$work/first.log" "$work/second.log" <<'PY'
import sys
sets=[]
for p in sys.argv[1:]:
    lines=open(p).read().splitlines()
    values={x.split('assignment=',1)[1] for x in lines if x.startswith('assignment=')}
    assert len(values)==2,(p,values)
    sets.append(values)
assert not (sets[0]&sets[1])
assert len(sets[0]|sets[1])==4
print('Real two-member disjoint complete Range assignment: PASS')
PY
    if [[ "${KAFKA_CONSUMER_LIVENESS:-0}" = 1 ]]; then
        for scenario in heartbeat lapse maxpoll reconnectclose; do
            timeout 50 "$work/client" "$topic-$scenario" "$scenario" "$topic" "$scenario" > "$work/$scenario.log" 2>&1
            cat "$work/$scenario.log"
        done
    fi
done
