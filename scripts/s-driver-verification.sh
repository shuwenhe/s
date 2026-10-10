#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

pass() { printf '%s PASS %s\n' "$1" "$2"; }
fail() { printf '%s FAIL %s\n' "$1" "$2"; exit 1; }
unverified() { printf '%s UNVERIFIED %s\n' "$1" "$2"; }

tmp=${TMPDIR:-/tmp}/s-driver-gate.$$
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

./bin/s_seed --compile-unit "$tmp/driver.ir" \
  src/cmd/compile/pipeline/pipeline.s \
  src/cmd/compile/driver/driver.s \
  src/cmd/compile/internal/tests/test_driver.s >/dev/null
pass D1 "argument parser compile check"

if ./bin/s test/cli/hello.s -o "$tmp/a" >/dev/null 2>&1 && \
   ./bin/s -o "$tmp/b" test/cli/hello.s >/dev/null 2>&1 && \
   ./bin/s build test/cli/hello.s -o "$tmp/c" >/dev/null 2>&1; then
    pass D2 "three build argument orders accepted by current CLI"
else
    fail D2 "build argument order compatibility failed"
fi

if ./bin/s -o >/dev/null 2>&1; then
    fail D3 "'s -o' unexpectedly succeeded"
else
    pass D3 "'s -o' rejected"
fi

if ./bin/s --emit-c test/cli/hello.s "$tmp/hello.c" >/dev/null 2>&1 && test -s "$tmp/hello.c"; then
    pass D4 "--emit-c forwarded through current CLI"
else
    fail D4 "--emit-c forwarding failed"
fi

if rg -q 'return pipeline_build\(config.input, config.output, "", false\)' src/cmd/compile/driver/driver.s && \
   rg -q 'std.process.exit\(pipeline_build\(args\[2\], args\[4\], "", false\)\)' src/cmd/compile/main.s && \
   rg -q 'func pipeline_compile\(pipeline_context context\) int' src/cmd/compile/pipeline/pipeline.s && \
   rg -q 'return backend_build\(context.input, context.output, context.ssa_margin_override, context.nostdlib\)' src/cmd/compile/pipeline/pipeline.s && \
   rg -q 'return compiler_main\(config.forwarded_args\)' src/cmd/compile/driver/driver.s; then
    unverified D5 "build routes through pipeline_build to backend authority; forwarded modes still route to compiler_main"
else
    fail D5 "driver dispatch shape changed; inspect authority route"
fi

if ./bin/s --help >/dev/null 2>&1 && ./misc/scripts/s-driver.sh --help >/dev/null 2>&1; then
    pass D6 "current CLI and shell driver both expose help"
else
    fail D6 "CLI/shell help comparison failed"
fi

make pipeline >/dev/null
pass D7 "bootstrap pipeline gate"

unverified OVERALL "S Driver present; canonical authority not proven"
