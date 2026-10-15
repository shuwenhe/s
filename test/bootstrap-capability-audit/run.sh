#!/usr/bin/env bash
# Audit only: report compiler behavior, including unexpectedly accepted negatives.
set -u
ulimit -c 0
root=$(cd "$(dirname "$0")/../.." && pwd)
out=$(mktemp -d /tmp/s-bootstrap-capability.XXXXXX)
printf 'artifacts=%s\n' "$out"
sha256sum "$root/bin/s_seed"
git -C "$root" rev-parse HEAD
printf 'case\tcompile_rc\temit_rc\truntime_rc\tstandalone_emit_rc\tstandalone_runtime_rc\n'
inputs=("$@")
if [ "${#inputs[@]}" -eq 0 ]; then
    inputs=("$root"/test/bootstrap-capability-audit/*.s)
fi
for input in "${inputs[@]}"; do
    name=$(basename "$input" .s)
    timeout 15s "$root/bin/s_seed" --compile-unit "$out/$name.ir" "$input" >"$out/$name.compile.log" 2>&1
    compile_rc=$?
    emit_rc=NA
    runtime_rc=NA
    standalone_emit_rc=NA
    standalone_runtime_rc=NA
    if [ "$compile_rc" -eq 0 ] && [ -s "$out/$name.ir" ]; then
        timeout 15s "$root/bin/s_seed" --emit-bin "$out/$name.ir" "$out/$name.bin" >"$out/$name.emit.log" 2>&1
        emit_rc=$?
        if [ "$emit_rc" -eq 0 ] && [ -x "$out/$name.bin" ]; then
            timeout 5s "$out/$name.bin" >"$out/$name.runtime.log" 2>&1
            runtime_rc=$?
        fi
        timeout 15s "$root/bin/s_seed" --emit-standalone-amd64 "$out/$name.ir" "$out/$name.native" >"$out/$name.standalone.log" 2>&1
        standalone_emit_rc=$?
        if [ "$standalone_emit_rc" -eq 0 ] && [ -x "$out/$name.native" ]; then
            timeout 5s "$out/$name.native" >"$out/$name.native-runtime.log" 2>&1
            standalone_runtime_rc=$?
        fi
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$compile_rc" "$emit_rc" "$runtime_rc" "$standalone_emit_rc" "$standalone_runtime_rc"
done
