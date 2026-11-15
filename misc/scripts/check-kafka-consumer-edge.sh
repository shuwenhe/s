#!/usr/bin/env bash
# Additional actual crash, fencing, survivor reassignment and live failover cases.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
source_file=${KAFKA_EDGE_SOURCE:-$root/test/kafka/consumer-edge/main.s}
run=${1:?fresh output directory}
[[ ! -e "$run" ]] || exit 2
mkdir -p "$run"
run=$(cd "$run" && pwd)
source misc/scripts/kafka-java.sh
kafka_test_java
export KAFKA_CACHE="$root/.bootstrap/kafka-broker/distribution"
export KAFKA_TEST_HEAP_OPTS='-Xms128m -Xmx512m'
export KAFKA_TEST_LOG_CLEANER_BUFFER_BYTES=8388608
source misc/scripts/kafka-broker.sh
child=
trap 'if [[ -n "$child" ]]; then kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; fi; kafka_stop' EXIT
kafka_start "$run/cluster" 29092 29093 29094
printf 'label\tcheck\texit\n' > "$run/status.tsv"
check() {
  local name=$1 status=0
  shift
  "$@" > "$work/$name.log" 2>&1 || status=$?
  printf '%s\t%s\t%s\n' "$label" "$name" "$status" >> "$run/status.tsv"
  cat "$work/$name.log"
  [[ "$status" = 0 ]]
}
create() { "$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "$KAFKA_BOOTSTRAP" --create --topic "$1" --replica-assignment "$2" >> "$work/topics.log" 2>&1; }
wait_ready() {
  local file=$1 pattern=$2
  for ((i=0;i<1200;i++)); do
    if rg -q "$pattern" "$file"; then return 0; fi
    kill -0 "$child" 2>/dev/null || { cat "$file"; return 1; }
    sleep 0.05
  done
  cat "$file"
  return 1
}
stop_node() {
  local id=$1 index pid config
  for index in "${!KAFKA_OWNED_PIDS[@]}"; do
    config=${KAFKA_OWNED_CONFIGS[$index]}; pid=${KAFKA_OWNED_PIDS[$index]}
    if [[ "$config" = "$KAFKA_WORKDIR/node-$id.properties" ]] && [[ -r /proc/$pid/cmdline ]] && tr '\0' '\n' < "/proc/$pid/cmdline" | grep -Fxq -- "$config"; then
      kill "$pid"
      for ((i=0;i<100;i++)); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
      if [[ -r /proc/$pid/cmdline ]] && tr '\0' '\n' < "/proc/$pid/cmdline" | grep -Fxq -- "$config"; then kill -KILL "$pid"; fi
      wait "$pid" 2>/dev/null || true
      printf 'stopped owned node=%s pid=%s\n' "$id" "$pid" >> "$work/failover-control.log"
      return 0
    fi
  done
  return 1
}
restart_node() {
  local id=$1 config="$KAFKA_WORKDIR/node-$1.properties" bootstrap="$KAFKA_BOOTSTRAP" ready=0
  KAFKA_HEAP_OPTS="$KAFKA_TEST_HEAP_OPTS" LOG_DIR="$KAFKA_WORKDIR/logs-$id" "$KAFKA_HOME/bin/kafka-server-start.sh" "$config" >> "$KAFKA_WORKDIR/node-$id.log" 2>&1 &
  KAFKA_OWNED_PIDS+=("$!"); KAFKA_OWNED_CONFIGS+=("$config")
  for ((i=0;i<60;i++)); do
    if "$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "$bootstrap" --describe --topic "$topic" > "$work/restart-$id.log" 2>&1 && python3 - "$work/restart-$id.log" <<'PY'
import sys,re
rows=[x for x in open(sys.argv[1]) if 'Partition:' in x]
assert rows and all(len(re.search(r'Isr: ([0-9,]+)',x).group(1).split(','))==2 for x in rows)
PY
    then ready=1; break; fi
    sleep 1
  done
  [[ "$ready" = 1 ]]
}
for label in ${KAFKA_EDGE_LABELS:-seed canonical stage2 stage3 stage4}; do
  compiler="$root/bin/s_compiler"
  [[ "$label" != seed ]] || compiler="$root/bin/s_seed"
  if [[ "$label" = stage* ]]; then compiler="${KAFKA_CONSUMER_STAGE_ROOT:-$root/.bootstrap/kafka-broker/phase1/selfhost}/$label"; fi
  work="$run/$label"; mkdir -p "$work"
  sha256sum "$compiler" "$source_file" src/std/kafka/*.s > "$work/source.sha256"
  compile=--compile-unit; emit=--emit-bin
  if [[ "$label" = seed ]]; then compile=--compile-native-unit; emit=--emit-standalone-amd64; fi
  "$compiler" "$compile" "$work/program.ir" "$source_file" src/std/kafka/*.s src/std/tcp.s src/std/time.s src/result/result.s src/prelude/prelude.s > "$work/build.log" 2>&1
  "$compiler" "$emit" "$work/program.ir" "$work/client" >> "$work/build.log" 2>&1
  prefix="s-edge-$label-$(date +%s)-$$"
  for kind in uncommitted committed; do
    topic="$prefix-crash-$kind"; create "$topic" '1:2'
    "$work/client" "crash-$kind" "$topic-group" "$topic" > "$work/crash-$kind.log" 2>&1 &
    child=$!
    wait_ready "$work/crash-$kind.log" '^crash-ready$'
    kill -KILL "$child"
    crash_status=0; wait "$child" || crash_status=$?; child=
    printf '%s\tcrash-%s-SIGKILL\t%s\n' "$label" "$kind" "$crash_status" >> "$run/status.tsv"
    [[ "$crash_status" = 137 ]]
    check "resume-$kind" timeout 60 "$work/client" "resume-$kind" "$topic-group" "$topic"
  done
  topic="$prefix-rebalance"; create "$topic" '1:2,1:2,2:1,2:1'
  check rebalance timeout 100 "$work/client" rebalance "$topic-group" "$topic"
  check unknown timeout 30 "$work/client" unknown "$prefix-unknown-group" "$prefix-does-not-exist"
  topic="$prefix-range-error"; create "$topic" '1:2'
  check range-error timeout 60 "$work/client" range-error "$topic-group" "$topic"
  for role in leader coordinator; do
    topic="$prefix-failover-$role"; create "$topic" '1:2'
    timeout 120 "$work/client" failover "$topic-group" "$topic" > "$work/failover-$role.log" 2>&1 &
    child=$!
    wait_ready "$work/failover-$role.log" '^failover-ready$'
    id=1
    if [[ "$role" = coordinator ]] && rg -q '^coordinator-port=29093$' "$work/failover-$role.log"; then id=2; fi
    stop_node "$id"
    status=0; wait "$child" || status=$?; child=
    printf '%s\tfailover-%s\t%s\n' "$label" "$role" "$status" >> "$run/status.tsv"
    cat "$work/failover-$role.log"
    [[ "$status" = 0 ]]
    restart_node "$id"
  done
  sha256sum -c "$work/source.sha256" > "$work/source-integrity.log"
done
