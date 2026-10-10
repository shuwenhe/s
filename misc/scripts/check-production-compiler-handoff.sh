#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler="$root/bin/s"

if [ ! -x "$compiler" ]; then
    echo "missing executable compiler: $compiler" >&2
    exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

cp "$root/test/cli/hello.s" "$work/hello world.s"

cd "$work"

log="$work/build.log"
if ! S_DRIVER_AUTHORITY_TRACE=1 "$compiler" "hello world.s" >"$work/build.out" 2>"$log"; then
    echo "production hello build failed" >&2
    cat "$log" >&2
    exit 1
fi

if grep -F "bootstrap-subset:" "$log" >/dev/null 2>&1; then
    echo "production build reached bootstrap subset parser" >&2
    cat "$log" >&2
    exit 1
fi

grep -F "driver-dispatch=production-build" "$log" >/dev/null 2>&1
grep -F "production-compiler-entry=bin/s_modular" "$log" >/dev/null 2>&1
grep -F "canonical-frontend-reached=PROVEN" "$log" >/dev/null 2>&1
grep -F "implicit-subset-delegation=NO" "$log" >/dev/null 2>&1

[ "$(./hello\ world)" = "Hello, world!" ]

echo "production-compiler-handoff=PROVEN"
