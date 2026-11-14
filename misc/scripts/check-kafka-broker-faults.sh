#!/usr/bin/env bash
# Both endpoints are compiled S. These are fault tests, not real Kafka acceptance.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
compiler=${1:-"$root/bin/s_compiler"}
label=${2:-native}
work="$root/.bootstrap/kafka-broker/$label"
mkdir -p "$work"
sh misc/scripts/build-kafka-broker-test.sh unit "$work/unit" "$compiler" > "$work/unit-build.log" 2>&1
"$work/unit"
sh misc/scripts/build-kafka-broker-test.sh fault-client "$work/client" "$compiler" > "$work/client-build.log" 2>&1
sh misc/scripts/build-kafka-broker-test.sh fault-peer "$work/peer" "$compiler" > "$work/peer-build.log" 2>&1
peer_pid=
cleanup() {
    if [[ -n "$peer_pid" ]]; then kill "$peer_pid" 2>/dev/null || true; wait "$peer_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT
# Refusal is checked before starting any listening peer.
timeout 10 "$work/client" refused
for mode in valid mismatch negative short oversize eof-header eof-body timeout slow decode-timeout write-timeout; do
    timeout 10 "$work/peer" "$mode" > "$work/peer-$mode.log" 2>&1 &
    peer_pid=$!
    ready=0
    for ((attempt=0; attempt<200; attempt++)); do
        if rg -q '^ready$' "$work/peer-$mode.log"; then ready=1; break; fi
        if ! kill -0 "$peer_pid" 2>/dev/null; then cat "$work/peer-$mode.log"; wait "$peer_pid"; exit 1; fi
        sleep 0.01
    done
    [[ "$ready" = 1 ]] || { echo "peer readiness timeout: $mode" >&2; exit 1; }
    timeout 10 "$work/client" "$mode"
    wait "$peer_pid"
    peer_pid=
done
printf 'Kafka broker unit and TCP faults (%s): PASS\n' "$label"
