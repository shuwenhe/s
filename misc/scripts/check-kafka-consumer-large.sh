#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
source_file="$root/test/kafka/consumer-large/main.s"
run=${1:?fresh evidence directory}
[[ ! -e "$run" ]] || exit 2
mkdir -p "$run"; run=$(cd "$run" && pwd)
source misc/scripts/kafka-java.sh
kafka_test_java
export KAFKA_CACHE="$root/.bootstrap/kafka-broker/distribution"
export KAFKA_TEST_HEAP_OPTS='-Xms128m -Xmx512m'
export KAFKA_TEST_LOG_CLEANER_BUFFER_BYTES=8388608
source misc/scripts/kafka-broker.sh
trap kafka_stop EXIT
kafka_start "$run/cluster" 39092 39093 39094
printf 'label\tcheck\texit\n' > "$run/status.tsv"
for label in ${KAFKA_LARGE_LABELS:-seed canonical stage2 stage3 stage4}; do
  compiler="$root/bin/s_compiler"
  [[ "$label" != seed ]] || compiler="$root/bin/s_seed"
  if [[ "$label" = stage* ]]; then compiler="${KAFKA_CONSUMER_STAGE_ROOT:-$root/.bootstrap/kafka-broker/phase1/selfhost}/$label"; fi
  work="$run/$label"; mkdir -p "$work"
  sha256sum "$compiler" "$source_file" src/std/kafka/*.s > "$work/source.sha256"
  compile=--compile-unit; emit=--emit-bin
  if [[ "$label" = seed ]]; then compile=--compile-native-unit; emit=--emit-standalone-amd64; fi
  "$compiler" "$compile" "$work/program.ir" "$source_file" src/std/kafka/*.s src/std/tcp.s src/std/time.s src/result/result.s src/prelude/prelude.s > "$work/build.log" 2>&1
  "$compiler" "$emit" "$work/program.ir" "$work/client" >> "$work/build.log" 2>&1
  topic="s-large-$label-$(date +%s)-$$"
  "$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "$KAFKA_BOOTSTRAP" --create --topic "$topic" --replica-assignment '1:2' > "$work/topic.log" 2>&1
  status=0
  /usr/bin/time -v -o "$work/resources.log" timeout 120 "$work/client" "$topic" "$topic-group" > "$work/client.log" 2>&1 || status=$?
  printf '%s\tlarge-default-deadline\t%s\n' "$label" "$status" >> "$run/status.tsv"
  cat "$work/client.log"
  [[ "$status" = 0 ]]
  sha256sum -c "$work/source.sha256" > "$work/source-integrity.log"
done
