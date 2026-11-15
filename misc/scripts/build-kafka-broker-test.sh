#!/bin/sh
# Pure S client/peer; seed or native stages emit standalone native executables.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
mode=${1:?usage: build-kafka-broker-test.sh MODE OUTPUT [COMPILER]}
output=${2:?missing OUTPUT}
compiler=${3:-"$root/bin/s_compiler"}
case "$output" in /*) ;; *) output="$PWD/$output" ;; esac
mkdir -p "$root/.bootstrap/kafka-broker"
work=$(mktemp -d "$root/.bootstrap/kafka-broker/build.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT HUP INT TERM
cd "$root"
export S_SOURCE_ROOT="$root"
case "$mode" in
    unit) set -- test/kafka/unit/*.s ;;
    consumer-commit-client) set -- test/kafka/consumer-commit-fault/client.s ;;
    consumer-commit-peer) set -- test/kafka/consumer-commit-fault/peer.s ;;
    consumer-large) set -- test/kafka/consumer-large/*.s ;;
    consumer-edge) set -- test/kafka/consumer-edge/*.s ;;
    consumer-unit) set -- test/kafka/consumer-unit/*.s ;;
    consumer-fault-client) set -- test/kafka/consumer-fault/client.s ;;
    consumer-fault-peer) set -- test/kafka/consumer-fault/peer.s ;;
    consumer-phase1) set -- test/kafka/consumer-phase1/*.s ;;
    consumer-group) set -- test/kafka/consumer-group/*.s ;;
    consumer-offsets) set -- test/kafka/consumer-offsets/*.s ;;
    consumer-scenarios) set -- test/kafka/consumer-scenarios/*.s ;;
    consumer-benchmark) set -- test/kafka/consumer-benchmark/main.s ;;
    producer-unit) set -- test/kafka/producer-unit/*.s ;;
    producer) set -- test/kafka/producer/*.s ;;
    producer-benchmark) set -- test/kafka/producer-benchmark/*.s ;;
    producer-fault-client) set -- test/kafka/producer-fault/client.s ;;
    producer-fault-peer) set -- test/kafka/producer-fault/peer.s ;;
    integration) set -- test/kafka/integration/*.s ;;
    fault-client) set -- test/kafka/fault/client.s ;;
    fault-peer) set -- test/kafka/fault/peer.s ;;
    *) echo "unknown mode: $mode" >&2; exit 2 ;;
esac
compile=--compile-unit
emit=--emit-bin
case "$compiler" in */s_seed) compile=--compile-native-unit; emit=--emit-standalone-amd64 ;; esac
"$compiler" "$compile" "$work/program.ir" "$@" src/std/kafka/*.s src/std/tcp.s src/std/time.s src/result/result.s src/prelude/prelude.s
"$compiler" "$emit" "$work/program.ir" "$work/program"
mkdir -p "$(dirname -- "$output")"
cp "$work/program" "$output"
chmod +x "$output"
