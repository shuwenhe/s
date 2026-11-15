#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
run=${1:?fresh evidence directory}
mkdir "$run";run=$(cd "$run" && pwd)
export S_SOURCE_ROOT="$root"
export JAVA_HOME="$root/.bootstrap/kafka-broker/java"
export PATH="$JAVA_HOME/bin:$PATH"
export KAFKA_CACHE="$root/.bootstrap/kafka-broker/distribution"
export KAFKA_TEST_HEAP_OPTS='-Xms128m -Xmx512m'
export KAFKA_TEST_LOG_CLEANER_BUFFER_BYTES=8388608
python3 - "$run/helper.sh" <<'PY'
import pathlib,sys
s=pathlib.Path('misc/scripts/kafka-broker.sh').read_text().replace("echo 'num.io.threads=2'","echo 'num.io.threads=2'\n            echo 'connections.max.idle.ms=5000'")
pathlib.Path(sys.argv[1]).write_text(s)
PY
source "$run/helper.sh"
child=
cleanup() { if [[ -n $child ]];then kill "$child" 2>/dev/null || true;wait "$child" 2>/dev/null || true;fi;kafka_stop; }
trap cleanup EXIT
kafka_start "$run/cluster" 49092 49093 49094
printf 'label\tmode\texit\n' > "$run/status.tsv"
for label in ${KAFKA_CLOSE_LABELS:-seed canonical stage2 stage3 stage4};do
 compiler="$root/bin/s_compiler";compile=--compile-unit;emit=--emit-bin
 if [[ $label == seed ]];then compiler="$root/bin/s_seed";compile=--compile-native-unit;emit=--emit-standalone-amd64;fi
 if [[ $label == stage* ]];then compiler="$root/.bootstrap/kafka-broker/phase1/selfhost/$label";fi
 work="$run/$label";mkdir "$work"
 sha256sum "$compiler" src/std/kafka/*.s > "$work/source.sha256"
 "$compiler" "$compile" "$work/program.ir" test/kafka/consumer-close-real/main.s src/std/kafka/*.s src/std/tcp.s src/std/time.s src/result/result.s src/prelude/prelude.s > "$work/build.log" 2>&1
 "$compiler" "$emit" "$work/program.ir" "$work/client" >> "$work/build.log" 2>&1
 for mode in normal idle expired restart;do
  topic="s-close-$label-$mode-$$"
  "$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "$KAFKA_BOOTSTRAP" --create --topic "$topic" --replica-assignment '1:2' > "$work/topic-$mode.log" 2>&1
  code=0
  if [[ $mode != restart ]];then
   timeout 90 "$work/client" "$topic" "$topic-group" "$mode" > "$work/$mode.log" 2>&1 || code=$?
  else
   timeout 150 "$work/client" "$topic" "$topic-group" "$mode" > "$work/$mode.log" 2>&1 &child=$!
   ready=0
   for ((i=0;i<1200;i++));do
    if rg -q '^restart-ready$' "$work/$mode.log";then ready=1;break;fi
    kill -0 "$child" 2>/dev/null || break;sleep .05
   done
   [[ $ready == 1 ]] || { cat "$work/$mode.log";exit 1; }
   kafka_stop
   kafka_start "$run/cluster" 49092 49093 49094
   python3 - <<'PY'
import socket
with socket.create_connection(('127.0.0.1',49095),timeout=3):pass
PY
   wait "$child" || code=$?;child=
  fi
  printf '%s\t%s\t%s\n' "$label" "$mode" "$code" >> "$run/status.tsv"
  cat "$work/$mode.log"
 done
 sha256sum -c "$work/source.sha256" > "$work/source-integrity.log"
done
python3 - "$run/status.tsv" <<'PY'
import csv,sys
r=list(csv.DictReader(open(sys.argv[1]),delimiter='\t'))
raise SystemExit(0 if r and all(x['exit']=='0' for x in r) else 1)
PY
