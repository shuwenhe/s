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
