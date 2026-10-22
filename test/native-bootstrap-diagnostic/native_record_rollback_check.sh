#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work="$root/.bootstrap/native-record-rollback"
mkdir -p "$work"
# Instrument a test-only copy; no fault switch is added to production runtime.
sed 's/call s_alloc$/call test_alloc/' "$root/src/runtime/selfhost_linux_amd64.S" > "$work/runtime.s"
cat "$root/test/native-bootstrap-diagnostic/native-records/rollback.S" >> "$work/runtime.s"
as --64 -o "$work/test.o" "$work/runtime.s"
ld -static -T "$root/src/runtime/linker/nostdlib.ld" -o "$work/test" "$work/test.o"
status=0; timeout 10 "$work/test" || status=$?
if [ "$status" -ne 42 ]; then echo "record rollback: expected 42, got $status" >&2; exit 1; fi
echo 'record copy initialization/failure rollback and independent storage: PASS'
