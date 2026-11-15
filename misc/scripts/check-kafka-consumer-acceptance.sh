#!/usr/bin/env bash
# Full fresh evidence; fixed socket ports are used serially. Compiler builds alone
# are parallel. No historical Phase1 path is used for output.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
run=${1:?fresh evidence directory}
[[ ! -e "$run" ]] || { echo "refusing to overwrite existing evidence: $run" >&2; exit 2; }
mkdir -p "$run"
run=$(cd "$run" && pwd)
source misc/scripts/kafka-java.sh
kafka_test_java
export KAFKA_CACHE="$root/.bootstrap/kafka-broker/distribution"
export KAFKA_TEST_HEAP_OPTS='-Xms128m -Xmx512m'
export KAFKA_TEST_LOG_CLEANER_BUFFER_BYTES=8388608
source misc/scripts/kafka-broker.sh
peer_pid=
child_one=
child_two=
child_three=
cleanup() {
    for pid in "$peer_pid" "$child_one" "$child_two" "$child_three"; do
        if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
    done
    kafka_stop
}
trap cleanup EXIT
kafka_start "$run/cluster" 9092 19093 19094
printf 'label\tcheck\texit\n' > "$run/status.tsv"
run_check() {
    local name=$1
    shift
    local status=0
    "$@" > "$work/$name.log" 2>&1 || status=$?
    printf '%s\t%s\t%s\n' "$label" "$name" "$status" >> "$run/status.tsv"
    cat "$work/$name.log"
    [[ "$status" = 0 ]] || { echo "FAIL $label $name exit=$status" >&2; return "$status"; }
}
create_topic() {
    "$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "$KAFKA_BOOTSTRAP" --create --topic "$1" --replica-assignment "$2" >> "$work/topics.log" 2>&1
}
for label in ${KAFKA_CONSUMER_LABELS:-seed canonical stage2 stage3 stage4}; do
    case "$label" in
        seed) compiler="$root/bin/s_seed" ;;
        canonical) compiler="$root/bin/s_compiler" ;;
        stage2|stage3|stage4) compiler="$root/.bootstrap/kafka-broker/phase1/selfhost/$label" ;;
        *) echo "unknown compiler label $label" >&2; exit 2 ;;
    esac
    work="$run/$label"
    mkdir -p "$work"
    sha256sum "$compiler" > "$work/compiler.sha256"
    sha256sum src/std/kafka/*.s test/kafka/consumer-*/*.s > "$work/source.sha256"
    pids=()
    modes=(consumer-unit consumer-fault-client consumer-fault-peer consumer-phase1 consumer-group consumer-offsets consumer-scenarios consumer-benchmark)
    for mode in "${modes[@]}"; do
        sh misc/scripts/build-kafka-broker-test.sh "$mode" "$work/$mode" "$compiler" > "$work/build-$mode.log" 2>&1 &
        pids+=("$!")
    done
    build_failed=0
    for i in "${!pids[@]}"; do
        status=0
        wait "${pids[$i]}" || status=$?
        printf '%s\tbuild-%s\t%s\n' "$label" "${modes[$i]}" "$status" >> "$run/status.tsv"
        if [[ "$status" != 0 ]]; then build_failed=1; cat "$work/build-${modes[$i]}.log"; fi
    done
    [[ "$build_failed" = 0 ]] || exit 1
    run_check unit "$work/consumer-unit"
    run_check refusal "$work/consumer-fault-client" refused
    for mode in valid mismatch negative short oversize eof-header eof-body timeout slow decode-timeout; do
        timeout 15 "$work/consumer-fault-peer" "$mode" > "$work/peer-$mode.log" 2>&1 &
        peer_pid=$!
        ready=0
        for ((i=0;i<300;i++)); do
            if rg -q '^ready$' "$work/peer-$mode.log"; then ready=1; break; fi
            kill -0 "$peer_pid" 2>/dev/null || break
            sleep 0.01
        done
        [[ "$ready" = 1 ]] || { cat "$work/peer-$mode.log"; exit 1; }
        run_check "fault-$mode" timeout 15 "$work/consumer-fault-client" "$mode"
        wait "$peer_pid"
        peer_pid=
    done
    topic="s-cv1-$label-$(date +%s)-$$"
    create_topic "$topic-phase1" '1:2,1:2'
    run_check phase1 timeout 90 "$work/consumer-phase1" "$topic-phase1"
    create_topic "$topic-offsets" '1:2'
    run_check offsets timeout 120 "$work/consumer-offsets" "$topic-offsets-group" "$topic-offsets"
    create_topic "$topic-a" '1:2,1:2'
    create_topic "$topic-b" '2:1,2:1'
    run_check multi timeout 90 "$work/consumer-scenarios" multi "$topic-multi-group" "$topic-a" "$topic-b"
    create_topic "$topic-latest" '1:2'
    run_check latest timeout 90 "$work/consumer-scenarios" latest "$topic-latest-group" "$topic-latest" unused
    create_topic "$topic-range" '1:2,1:2,2:1,2:1'
    run_check group-single timeout 50 "$work/consumer-group" "$topic-single-group" single "$topic-range" single
    timeout 50 "$work/consumer-group" "$topic-pair-group" first "$topic-range" pair > "$work/group-first.log" 2>&1 &
    child_one=$!
    timeout 50 "$work/consumer-group" "$topic-pair-group" second "$topic-range" pair > "$work/group-second.log" 2>&1 &
    child_two=$!
    first=0; second=0
    wait "$child_one" || first=$?
    wait "$child_two" || second=$?
    child_one=; child_two=
    cat "$work/group-first.log" "$work/group-second.log"
    printf '%s\tgroup-first\t%s\n%s\tgroup-second\t%s\n' "$label" "$first" "$label" "$second" >> "$run/status.tsv"
    [[ "$first" = 0 && "$second" = 0 ]] || exit 1
    python3 - "$work/group-first.log" "$work/group-second.log" <<'PY'
import sys
sets=[{x.split('assignment=',1)[1].strip() for x in open(p) if x.startswith('assignment=')} for p in sys.argv[1:]]
assert len(sets[0])==2 and len(sets[1])==2 and not sets[0]&sets[1] and len(sets[0]|sets[1])==4
print('Real concurrent Range disjoint/complete assignment: PASS')
PY
    create_topic "$topic-empty" '1:2'
    timeout 50 "$work/consumer-group" "$topic-empty-group" first "$topic-empty" empty > "$work/empty-first.log" 2>&1 &
    child_one=$!
    timeout 50 "$work/consumer-group" "$topic-empty-group" second "$topic-empty" empty > "$work/empty-second.log" 2>&1 &
    child_two=$!
    timeout 50 "$work/consumer-group" "$topic-empty-group" third "$topic-empty" empty > "$work/empty-third.log" 2>&1 &
    child_three=$!
    first=0; second=0; third=0
    wait "$child_one" || first=$?
    wait "$child_two" || second=$?
    wait "$child_three" || third=$?
    child_one=; child_two=; child_three=
    printf '%s\tempty-first\t%s\n%s\tempty-second\t%s\n%s\tempty-third\t%s\n' "$label" "$first" "$label" "$second" "$label" "$third" >> "$run/status.tsv"
    [[ "$first" = 0 && "$second" = 0 && "$third" = 0 ]] || exit 1
    python3 - "$work/empty-first.log" "$work/empty-second.log" "$work/empty-third.log" <<'PYEMPTY'
import sys
sets=[{x.split('assignment=',1)[1].strip() for x in open(p) if x.startswith('assignment=')} for p in sys.argv[1:]]
assert sorted(map(len,sets))==[0,0,1] and len(set.union(*sets))==1
print('Real three-member/one-partition empty assignments: PASS')
PYEMPTY
    for scenario in heartbeat lapse maxpoll reconnectclose; do
        run_check "$scenario" timeout 55 "$work/consumer-group" "$topic-$scenario-group" "$scenario" "$topic-range" "$scenario"
    done
    create_topic "$topic-processing" '1:2'
    run_check processing timeout 60 "$work/consumer-scenarios" processing "$topic-processing-group" "$topic-processing" unused
    create_topic "$topic-growth" '1:2'
    timeout 70 "$work/consumer-group" "$topic-growth-group" growth "$topic-growth" growth > "$work/growth.log" 2>&1 &
    child_one=$!
    ready=0
    for ((i=0;i<600;i++)); do
        if rg -q 'count=1$' "$work/growth.log"; then ready=1; break; fi
        kill -0 "$child_one" 2>/dev/null || break
        sleep 0.05
    done
    [[ "$ready" = 1 ]] || { cat "$work/growth.log"; exit 1; }
    "$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "$KAFKA_BOOTSTRAP" --alter --topic "$topic-growth" --partitions 2 >> "$work/topics.log" 2>&1
    growth_status=0
    wait "$child_one" || growth_status=$?
    child_one=
    printf '%s\tgrowth\t%s\n' "$label" "$growth_status" >> "$run/status.tsv"
    cat "$work/growth.log"
    [[ "$growth_status" = 0 ]] || exit 1
    # Full owned cluster loss/restart. This is an actual broker failure, not a peer.
    create_topic "$topic-recovery" '1:2'
    timeout 120 "$work/consumer-scenarios" recovery "$topic-recovery-group" "$topic-recovery" unused > "$work/recovery.log" 2>&1 &
    child_one=$!
    ready=0
    for ((i=0;i<600;i++)); do
        if rg -q '^recovery-ready$' "$work/recovery.log"; then ready=1; break; fi
        kill -0 "$child_one" 2>/dev/null || break
        sleep 0.05
    done
    [[ "$ready" = 1 ]] || { cat "$work/recovery.log"; exit 1; }
    kafka_stop
    kafka_start "$run/cluster" 9092 19093 19094
    recovery_status=0
    wait "$child_one" || recovery_status=$?
    child_one=
    printf '%s\trecovery\t%s\n' "$label" "$recovery_status" >> "$run/status.tsv"
    cat "$work/recovery.log"
    [[ "$recovery_status" = 0 ]] || exit 1
    for style in single batch; do
        create_topic "$topic-bench-$style" '1:2'
        run_check "benchmark-$style" /usr/bin/time -v -o "$work/resources-$style.log" python3 test/kafka/consumer-benchmark/measure.py "$work/measure-$style" "$work/consumer-benchmark" "$topic-bench-$style" "$topic-bench-$style-group" "$style"
    done
    sha256sum -c "$work/source.sha256" > "$work/source-integrity.log"
    printf 'Consumer acceptance %s: PASS\n' "$label"
done
printf 'Consumer requested compiler matrix: PASS\n'
