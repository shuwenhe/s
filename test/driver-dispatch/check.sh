#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-driver-dispatch.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

"$root/bin/s_seed" --compile-unit "$work/driver.ir" \
    "$root/src/cmd/compile/internal/driver/driver.s" \
    "$root/test/driver-dispatch/driver_test.s"
"$root/bin/s_seed" --emit-bin "$work/driver.ir" "$work/driver"

failed=0
if ! "$work/driver" test-parse; then failed=1; fi
if ! "$work/driver" test-dispatch >"$work/dispatch.txt" 2>&1; then
    cat "$work/dispatch.txt" >&2
    failed=1
fi
"$work/driver" --help >"$work/help.txt" 2>&1
grep -Fq -- '--emit-c' "$work/help.txt"
if ! grep -Fq -- 'stage5-name-resolution-proof' "$work/help.txt" ||
   ! grep -Fq -- 'canonical-regalloc-proof' "$work/help.txt"; then
    echo 'Proof commands are not discoverable through --help' >&2
    failed=1
fi
if [ "$failed" -ne 0 ]; then exit "$failed"; fi

printf '%s\n' 'Driver proof and emit dispatch checks passed'
