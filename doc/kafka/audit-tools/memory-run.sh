#!/usr/bin/env bash
set -euo pipefail
cd /root/shuwen/s
run="$PWD/.bootstrap/kafka-audit/audit-20261115"
export S_SOURCE_ROOT="$PWD"
for label in seed canonical; do
 compiler="$PWD/bin/s_compiler";compile=--compile-unit;emit=--emit-bin
 if [[ $label == seed ]]; then compiler="$PWD/bin/s_seed";compile=--compile-native-unit;emit=--emit-standalone-amd64;fi
 "$compiler" "$compile" "$run/memory-$label.ir" "$run/memory.s" src/std/kafka/*.s src/std/tcp.s src/std/time.s src/result/result.s src/prelude/prelude.s > "$run/memory-build-$label.log" 2>&1
 "$compiler" "$emit" "$run/memory-$label.ir" "$run/memory-$label" >> "$run/memory-build-$label.log" 2>&1
done
export JAVA_HOME="$PWD/.bootstrap/kafka-broker/java"
export PATH="$JAVA_HOME/bin:$PATH"
export KAFKA_CACHE="$PWD/.bootstrap/kafka-broker/distribution"
export KAFKA_TEST_HEAP_OPTS='-Xms128m -Xmx512m'
export KAFKA_TEST_LOG_CLEANER_BUFFER_BYTES=8388608
source misc/scripts/kafka-broker.sh
trap kafka_stop EXIT
kafka_start "$run/memory-cluster" 39092 39093 39094
javac -cp "$KAFKA_HOME/libs/*" "$run/AuditProducer.java" > "$run/java-build.log" 2>&1
printf 'label\tbytes\tseconds\texit\n' > "$run/memory-status.tsv"
# Start the sustained canonical case before the size sweep.
topic="audit-sustained-$$"
"$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "$KAFKA_BOOTSTRAP" --create --topic "$topic" --replica-assignment '1:2' > "$run/topic-sustained.log" 2>&1
java -cp "$KAFKA_HOME/libs/*:$run" AuditProducer "$topic" 1024 > "$run/produce-sustained.log" 2>&1
python3 "$run/measure.py" "$run/memory-sustained" "$run/memory-canonical" "$topic" 1024 1800 0 > "$run/sustained-summary.log" 2>&1 &
sustained_pid=$!
for size in 1024 16384 65536 262144 524288 1048576;do
 topic="audit-size-$size-$$"
 "$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "$KAFKA_BOOTSTRAP" --create --topic "$topic" --replica-assignment '1:2' --config max.message.bytes=2097152 > "$run/topic-$size.log" 2>&1
 java -cp "$KAFKA_HOME/libs/*:$run" AuditProducer "$topic" "$size" > "$run/produce-$size.log" 2>&1
 for label in seed canonical;do
  # Distinct topics/groups ensure initial offsets are identical for each compiler.
  label_topic="$topic-$label"
  "$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "$KAFKA_BOOTSTRAP" --create --topic "$label_topic" --replica-assignment '1:2' --config max.message.bytes=2097152 > "$run/topic-$size-$label.log" 2>&1
  java -cp "$KAFKA_HOME/libs/*:$run" AuditProducer "$label_topic" "$size" > "$run/produce-$size-$label.log" 2>&1
  status=0
  python3 "$run/measure.py" "$run/memory-$size-$label" "$run/memory-$label" "$label_topic" "$size" 0 16 > "$run/summary-$size-$label.log" 2>&1 || status=$?
  printf '%s\t%s\t0\t%s\n' "$label" "$size" "$status" >> "$run/memory-status.tsv"
 done
done
status=0;wait "$sustained_pid" || status=$?
printf 'canonical\t1024\t1800\t%s\n' "$status" >> "$run/memory-status.tsv"
