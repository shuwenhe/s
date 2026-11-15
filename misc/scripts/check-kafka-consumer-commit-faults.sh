#!/usr/bin/env bash
# Native coordinator fixture. This complements, and is not, real broker testing.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
run=${1:?fresh evidence directory}
[[ ! -e "$run" ]] || exit 2
mkdir -p "$run"
run=$(cd "$run" && pwd)
peer_pid=
trap 'if [[ -n "$peer_pid" ]]; then kill "$peer_pid" 2>/dev/null || true; wait "$peer_pid" 2>/dev/null || true; fi' EXIT
printf 'label\tcheck\texit\n' > "$run/status.tsv"
for label in seed canonical stage2 stage3 stage4; do
    compiler="$root/bin/s_compiler"
    if [[ "$label" = seed ]]; then compiler="$root/bin/s_seed"; fi
    if [[ "$label" = stage* ]]; then compiler="$root/.bootstrap/kafka-broker/phase1/selfhost/$label"; fi
    work="$run/$label"
    mkdir -p "$work"
    sha256sum "$compiler" > "$work/compiler.sha256"
    for mode in client peer; do
        sh misc/scripts/build-kafka-broker-test.sh "consumer-commit-$mode" "$work/$mode" "$compiler" > "$work/build-$mode.log" 2>&1
    done
    for mode in lost timeout partial auth; do
        timeout 15 "$work/peer" "$mode" > "$work/peer-$mode.log" 2>&1 &
        peer_pid=$!
        ready=0
        for ((i=0;i<300;i++)); do
            if rg -q '^ready$' "$work/peer-$mode.log"; then ready=1; break; fi
            kill -0 "$peer_pid" 2>/dev/null || break
            sleep 0.01
        done
        [[ "$ready" = 1 ]] || { cat "$work/peer-$mode.log"; exit 1; }
        status=0
        timeout 10 "$work/client" "$mode" > "$work/client-$mode.log" 2>&1 || status=$?
        printf '%s\t%s\t%s\n' "$label" "$mode" "$status" >> "$run/status.tsv"
        [[ "$status" = 0 ]] || { cat "$work/client-$mode.log"; exit 1; }
        wait "$peer_pid"
        peer_pid=
        cat "$work/client-$mode.log" "$work/peer-$mode.log"
    done
done
