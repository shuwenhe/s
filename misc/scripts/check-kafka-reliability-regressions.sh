#!/usr/bin/env bash
set -u
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
run=${1:?remediation evidence root}
printf 'check\texit\n' > "$run/regression-status.tsv"
check() { name=$1;shift;code=0;"$@" > "$run/$name.log" 2>&1 || code=$?;printf '%s\t%s\n' "$name" "$code" >> "$run/regression-status.tsv"; }
check consumer-full bash misc/scripts/check-kafka-consumer-acceptance.sh "$run/consumer-full"
check consumer-close bash misc/scripts/check-kafka-consumer-close.sh "$run/consumer-close"
check commit-fault bash misc/scripts/check-kafka-consumer-commit-faults.sh "$run/commit-fault"
for label in seed canonical stage2 stage3 stage4;do
 compiler="$root/bin/s_compiler"
 if [[ $label == seed ]];then compiler="$root/bin/s_seed";fi
 if [[ $label == stage* ]];then compiler="$root/.bootstrap/kafka-broker/phase1/selfhost/$label";fi
 sha256sum "$compiler" > "$run/compiler-$label.sha256"
 check "producer-fault-$label" bash "$run/check-kafka-producer-faults.sh" "$compiler" "$label"
 check "broker-fault-$label" bash "$run/check-kafka-broker-faults.sh" "$compiler" "$label"
done
export JAVA_HOME="$root/.bootstrap/kafka-broker/java"
export PATH="$JAVA_HOME/bin:$PATH"
check producer-real bash "$run/check-kafka-producer-real.sh"
for label in seed canonical stage2 stage3 stage4;do
 compiler="$root/bin/s_compiler"
 if [[ $label == seed ]];then compiler="$root/bin/s_seed";fi
 if [[ $label == stage* ]];then compiler="$root/.bootstrap/kafka-broker/phase1/selfhost/$label";fi
 check "broker-real-$label" bash "$run/check-kafka-broker-real.sh" "$compiler" "$label"
done
python3 - "$run/regression-status.tsv" <<'PY'
import csv,sys
rows=list(csv.DictReader(open(sys.argv[1]),delimiter='\t'))
raise SystemExit(0 if rows and all(r['exit']=='0' for r in rows) else 1)
PY
