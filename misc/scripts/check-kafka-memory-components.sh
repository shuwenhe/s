#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
run=${1:?fresh evidence directory}
mkdir "$run";run=$(cd "$run" && pwd)
export S_SOURCE_ROOT="$root"
printf 'label\tmode\texit\n' > "$run/status.tsv"
for label in seed canonical;do
 compiler="$root/bin/s_compiler";compile=--compile-unit;emit=--emit-bin
 if [[ $label == seed ]];then compiler="$root/bin/s_seed";compile=--compile-native-unit;emit=--emit-standalone-amd64;fi
 "$compiler" "$compile" "$run/$label.ir" test/kafka/consumer-memory/components.s src/std/kafka/*.s src/std/tcp.s src/std/time.s src/result/result.s src/prelude/prelude.s > "$run/build-$label.log" 2>&1
 if [[ $label == seed ]];then
  python3 test/kafka/consumer-memory/instrument.py "$run/seed-root" seed
  S_SOURCE_ROOT="$run/seed-root" "$compiler" "$emit" "$run/$label.ir" "$run/$label" >> "$run/build-$label.log" 2>&1
 else
  python3 test/kafka/consumer-memory/instrument.py "$run" canonical "$run/$label.ir"
  "$compiler" "$emit" "$run/memory-canonical-instrumented.ir" "$run/$label" >> "$run/build-$label.log" 2>&1
 fi
 for mode in fragments decode tcp-bytes;do
  code=0;python3 test/kafka/consumer-memory/measure.py "$run/$label-$mode" "$run/$label" "$mode" > "$run/$label-$mode.log" 2>&1 || code=$?
  printf '%s\t%s\t%s\n' "$label" "$mode" "$code" >> "$run/status.tsv"
 done
done
