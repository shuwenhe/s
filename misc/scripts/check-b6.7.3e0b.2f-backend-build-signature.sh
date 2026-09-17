#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
tmp="${TMPDIR:-/tmp}/b6.7.3e0b.2f-backend-build-signature.$$"

rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

signature='compile.internal.backend_elf64.build|4|4|int'
meta="$root/src/cmd/compile/seed/semantic/import_signatures.meta"

signature_present=NO
if grep -Fxq "$signature" "$meta"; then
    signature_present=YES
fi

set +e
"$root/bin/s_seed" "$root/src/cmd/compile/modular_build_main.s" "$tmp/modular_build_main.ir" >"$tmp/seed.log" 2>&1
status=$?
set -e

old_backend_build_any_error=NO
if grep -q "type 'any' has no method 'build'" "$tmp/seed.log"; then
    old_backend_build_any_error=YES
fi

echo "B6.7.3e0b.2f Backend Build Signature Gate"
echo "signature-present=$signature_present"
echo "seed-status=$status"
echo "old-backend-build-any-error=$old_backend_build_any_error"
if [ -s "$tmp/seed.log" ]; then
    sed 's/^/seed-diagnostic=/' "$tmp/seed.log"
fi

if [ "$signature_present" != YES ]; then
    exit 1
fi
if [ "$old_backend_build_any_error" = YES ]; then
    exit 1
fi
