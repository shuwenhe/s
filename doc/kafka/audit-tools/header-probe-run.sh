#!/usr/bin/env bash
set -eu
cd /root/shuwen/s
export S_SOURCE_ROOT="$PWD"
run="$PWD/.bootstrap/kafka-audit/audit-20261115"
printf 'label\tbuild_exit\trun_exit\n' > "$run/header-probe-status.tsv"
for label in seed canonical;do
 compiler="$PWD/bin/s_compiler";compile=--compile-unit;emit=--emit-bin
 if [ "$label" = seed ];then compiler="$PWD/bin/s_seed";compile=--compile-native-unit;emit=--emit-standalone-amd64;fi
 "$compiler" "$compile" "$run/header-probe-$label.ir" "$run/header-probe.s" src/std/kafka/*.s src/std/tcp.s src/std/time.s src/result/result.s src/prelude/prelude.s > "$run/header-probe-build-$label.log" 2>&1
 "$compiler" "$emit" "$run/header-probe-$label.ir" "$run/header-probe-$label" >> "$run/header-probe-build-$label.log" 2>&1
 "$run/header-probe-$label" > "$run/header-probe-$label.log" 2>&1
 printf '%s\t0\t0\n' "$label" >> "$run/header-probe-status.tsv"
done
