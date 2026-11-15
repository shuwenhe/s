#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
run=${1:?fresh evidence directory}
mkdir "$run";run=$(cd "$run" && pwd)
export S_SOURCE_ROOT="$root"
first=${KAFKA_SUSTAINED_PORT:-59092}
python3 - "$run" "$first" <<'PY'
from pathlib import Path
import sys
r=Path(sys.argv[1])
(r/'memory.s').write_text(Path('test/kafka/consumer-memory/main.s').read_text().replace('39092',sys.argv[2]))
(r/'AuditProducer.java').write_text(Path('doc/kafka/audit-tools/AuditProducer.java').read_text().replace('39092',sys.argv[2]))
PY
sha256sum bin/s_compiler src/std/kafka/*.s src/std/tcp.s "$run/memory.s" > "$run/source.sha256"
bin/s_compiler --compile-unit "$run/base.ir" "$run/memory.s" src/std/kafka/*.s src/std/tcp.s src/std/time.s src/result/result.s src/prelude/prelude.s > "$run/build.log" 2>&1
python3 test/kafka/consumer-memory/instrument.py "$run" canonical "$run/base.ir"
bin/s_compiler --emit-bin "$run/memory-canonical-instrumented.ir" "$run/client" >> "$run/build.log" 2>&1
export JAVA_HOME="$root/.bootstrap/kafka-broker/java"
export PATH="$JAVA_HOME/bin:$PATH"
export KAFKA_CACHE="$root/.bootstrap/kafka-broker/distribution"
export KAFKA_TEST_HEAP_OPTS='-Xms128m -Xmx512m'
export KAFKA_TEST_LOG_CLEANER_BUFFER_BYTES=8388608
source misc/scripts/kafka-broker.sh
trap kafka_stop EXIT
kafka_start "$run/cluster" "$first" "$((first+1))" "$((first+2))"
javac -cp "$KAFKA_HOME/libs/*" "$run/AuditProducer.java" > "$run/java-build.log" 2>&1
topic="s-remediation-sustained-$$"
"$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "$KAFKA_BOOTSTRAP" --create --topic "$topic" --replica-assignment '1:2' > "$run/topic.log" 2>&1
java -cp "$KAFKA_HOME/libs/*:$run" AuditProducer "$topic" 1024 > "$run/produce.log" 2>&1
status=0
python3 test/kafka/consumer-memory/measure.py "$run/measure" "$run/client" "$topic" 1024 1800 0 > "$run/measure.log" 2>&1 || status=$?
printf '%s\n' "$status" > "$run/client.exit"
sha256sum -c "$run/source.sha256" > "$run/source-integrity.log"
exit "$status"
