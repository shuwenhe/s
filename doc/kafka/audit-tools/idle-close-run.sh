#!/usr/bin/env bash
set -euo pipefail
cd /root/shuwen/s
run="$PWD/.bootstrap/kafka-audit/audit-20261115"
export JAVA_HOME="$PWD/.bootstrap/kafka-broker/java"
export PATH="$JAVA_HOME/bin:$PATH"
export KAFKA_CACHE="$PWD/.bootstrap/kafka-broker/distribution"
export KAFKA_TEST_HEAP_OPTS='-Xms128m -Xmx512m'
export KAFKA_TEST_LOG_CLEANER_BUFFER_BYTES=8388608
export S_SOURCE_ROOT="$PWD"
source "$run/idle-broker-helper.sh"
trap kafka_stop EXIT
kafka_start "$run/idle-close-cluster" 49092 49093 49094
"$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "$KAFKA_BOOTSTRAP" --create --topic audit-idle-close --replica-assignment '1:2' > "$run/idle-close-topic.log" 2>&1
printf 'label\tbuild_exit\trun_exit\n' > "$run/idle-close-status.tsv"
for label in seed canonical;do
 compiler="$PWD/bin/s_compiler";compile=--compile-unit;emit=--emit-bin
 if [[ $label == seed ]];then compiler="$PWD/bin/s_seed";compile=--compile-native-unit;emit=--emit-standalone-amd64;fi
 "$compiler" "$compile" "$run/idle-close-$label.ir" "$run/idle-close.s" src/std/kafka/*.s src/std/tcp.s src/std/time.s src/result/result.s src/prelude/prelude.s > "$run/idle-close-build-$label.log" 2>&1
 "$compiler" "$emit" "$run/idle-close-$label.ir" "$run/idle-close-$label" >> "$run/idle-close-build-$label.log" 2>&1
 status=0
 timeout 40 "$run/idle-close-$label" "audit-idle-$label" idle audit-idle-close heartbeat > "$run/idle-close-$label.log" 2>&1 || status=$?
 printf '%s\t0\t%s\n' "$label" "$status" >> "$run/idle-close-status.tsv"
done
