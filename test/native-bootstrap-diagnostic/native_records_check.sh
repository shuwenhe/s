#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work="$root/.bootstrap/native-records"
mkdir -p "$work"
cases=("${@}")
if [ "${#cases[@]}" -eq 0 ]; then cases=(nested_call copy_matrix defaults array_records callee_saved array_cycle order); fi
for name in "${cases[@]}"; do
    source="$root/test/native-bootstrap-diagnostic/native-records/$name.s"
    "$root/bin/s_seed" --compile-native-unit "$work/$name.ir" "$source"
    S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-hosted-program "$work/$name.ir" "$work/$name.hosted"
    status=0; timeout 10 "$work/$name.hosted" > "$work/$name.hosted.log" 2>&1 || status=$?
    if [ "$status" -ne 42 ]; then cat "$work/$name.hosted.log"; echo "$name hosted: expected 42, got $status" >&2; exit 1; fi
    S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/$name.ir" "$work/$name.native"
    status=0; timeout 10 "$work/$name.native" > "$work/$name.native.log" 2>&1 || status=$?
    if [ "$status" -ne 42 ]; then cat "$work/$name.native.log"; echo "$name native: expected 42, got $status" >&2; exit 1; fi
    printf '%s: hosted/native PASS (42)\n' "$name"
done
