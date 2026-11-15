#!/usr/bin/env bash
set -u
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
run=${1:?fresh evidence directory};mkdir "$run" || exit 2
run=$(cd "$run" && pwd)
export S_SOURCE_ROOT="$root"
printf 'label\tbuild_exit\trun_exit\n' > "$run/status.tsv"
for label in seed canonical stage2 stage3 stage4;do
 compiler="$root/bin/s_compiler";compile=--compile-unit;emit=--emit-bin
 if [[ $label == seed ]];then compiler="$root/bin/s_seed";compile=--compile-native-unit;emit=--emit-standalone-amd64;fi
 if [[ $label == stage* ]];then compiler="$root/.bootstrap/kafka-broker/phase1/selfhost/$label";fi
 build=0;code=BLOCKED
 "$compiler" "$compile" "$run/$label.ir" test/kafka/consumer-lifecycle/main.s src/std/kafka/*.s src/std/tcp.s src/std/time.s src/result/result.s src/prelude/prelude.s > "$run/$label-build.log" 2>&1 && "$compiler" "$emit" "$run/$label.ir" "$run/$label" >> "$run/$label-build.log" 2>&1 || build=$?
 if [[ $build == 0 ]];then code=0;timeout 10 "$run/$label" > "$run/$label.log" 2>&1 || code=$?;fi
 printf '%s\t%s\t%s\n' "$label" "$build" "$code" >> "$run/status.tsv"
done
python3 - "$run/status.tsv" <<'PY'
import csv,sys
rows=list(csv.DictReader(open(sys.argv[1]),delimiter='\t'))
raise SystemExit(0 if rows and all(r['build_exit']=='0' and r['run_exit']=='0' for r in rows) else 1)
PY
