#!/usr/bin/env bash
set -u
cd /root/shuwen/s
export S_SOURCE_ROOT="$PWD"
run="$PWD/.bootstrap/kafka-audit/audit-20261115"
printf 'label\tbuild_exit\trun_exit\n' > "$run/probe-status.tsv"
for label in seed canonical stage2 stage3 stage4;do
 compiler="$PWD/bin/s_compiler";compile=--compile-unit;emit=--emit-bin
 if [[ $label == seed ]];then compiler="$PWD/bin/s_seed";compile=--compile-native-unit;emit=--emit-standalone-amd64;fi
 if [[ $label == stage* ]];then compiler="$PWD/.bootstrap/kafka-broker/phase1/selfhost/$label";fi
 sha256sum "$compiler" > "$run/identity-$label.sha256"
 file "$compiler" > "$run/identity-$label.txt"
 status=0
 "$compiler" "$compile" "$run/probe-$label.ir" "$run/probe.s" src/std/kafka/*.s src/std/tcp.s src/std/time.s src/result/result.s src/prelude/prelude.s > "$run/probe-build-$label.log" 2>&1 && "$compiler" "$emit" "$run/probe-$label.ir" "$run/probe-$label" >> "$run/probe-build-$label.log" 2>&1 || status=$?
 code=BLOCKED
 if [[ $status == 0 ]];then code=0;timeout 60 "$run/probe-$label" > "$run/probe-$label.log" 2>&1 || code=$?;fi
 printf '%s\t%s\t%s\n' "$label" "$status" "$code" >> "$run/probe-status.tsv"
done
